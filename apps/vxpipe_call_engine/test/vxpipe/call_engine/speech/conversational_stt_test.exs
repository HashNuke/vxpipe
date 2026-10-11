defmodule Vxpipe.CallEngine.Speech.ConversationalSTTTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{CapabilityTree, ConversationalSTT, Event, Session}
  alias Vxpipe.CallEngine.SpeechOnsetProbe

  test "default onset ignores native hints until words, using one acknowledged outer allocation" do
    session = start_session(false)
    assert_receive {:recognizer, recognizer, inner}
    assert inner != session
    ready = event(session, :ready)
    assert ready.readiness == :initialized
    assert {:ok, descriptor} = Session.describe(session)
    assert descriptor.settings.vad == false
    assert descriptor.speech_start_evidence == :transcript
    native = make_ref()
    assert :ok = emit(recognizer, :speech_started, turn_ref: native)
    assert :ok = emit(recognizer, :transcript, turn_ref: native, text: "   ")
    # The inner channel is drained before inspecting the outer channel.
    assert :ok = GenServer.call(Session.provider(session), :synchronize)
    refute_received {:vxpipe_speech, %Event{session: ^session}}
    assert :ok = emit(recognizer, :transcript, turn_ref: native, text: "hello")
    start = event(session, :speech_started)
    transcript = event(session, :transcript)
    assert transcript.text == "hello"
    assert transcript.turn_ref == start.turn_ref
    refute start.turn_ref == native

    assert :ok =
             emit(recognizer, :turn_ended,
               turn_ref: native,
               text: "hello",
               endpointing: :provider_gap
             )

    assert event(session, :turn_ended).turn_ref == start.turn_ref
  end

  test "VAD off prepares no detector, forwards input once, and owner retirement closes recognizer" do
    session = start_session(false, load: fn -> flunk("VAD-off loaded Silero") end)
    assert_receive {:recognizer, recognizer, _inner}
    _ = event(session, :ready)
    assert :ok = Session.push_audio(session, <<1, 2, 3>>)
    assert_receive {:recognized_audio, <<1, 2, 3>>}
    refute_received {:recognized_audio, _}
    monitor = Process.monitor(recognizer)
    assert :ok = Session.close(session)
    assert_receive {:DOWN, ^monitor, :process, ^recognizer, _}
  end

  test "optional detector starts before words and is correlated to the recognizer's turn" do
    observer = self()

    classify = fn _model, stream, audio ->
      send(observer, {:classified, audio})
      count = div(byte_size(audio), 1_024)
      {:ok, %{stream | samples: stream.samples + count * 512}, List.duplicate(0.9, count)}
    end

    session = start_session(true, load: fn -> {:ok, :fake_model} end, classify: classify)
    assert_receive {:recognizer, recognizer, _inner}
    _ = event(session, :ready)
    assert_receive {:classified, warmup}
    assert warmup == :binary.copy(<<0>>, 1_024)
    assert {:ok, descriptor} = Session.describe(session)
    assert descriptor.speech_start_evidence == :local_acoustic
    pcm = :binary.copy(<<10, 0>>, 2_048)
    assert :ok = Session.push_audio(session, pcm)
    assert_receive {:recognized_audio, ^pcm}
    assert_receive {:classified, ^pcm}
    start = event(session, :speech_started)
    native = make_ref()
    assert :ok = emit(recognizer, :speech_started, turn_ref: native)
    assert :ok = emit(recognizer, :transcript, turn_ref: native, text: "hello")
    assert event(session, :transcript).turn_ref == start.turn_ref

    assert :ok =
             emit(recognizer, :turn_ended,
               turn_ref: native,
               text: "hello",
               endpointing: :provider_gap
             )

    assert event(session, :turn_ended).turn_ref == start.turn_ref
    refute_received {:vxpipe_speech, %Event{session: ^session, kind: :speech_started}}
  end

  test "detector preparation failure fails allocation rather than silently changing mode" do
    session = start_session(true, load: fn -> {:error, :not_available} end)
    tree = Session.tree(session)
    monitor = if tree, do: Process.monitor(tree)
    assert_receive {:vxpipe_speech_closed, ^session, reason}, 1_000
    assert reason in [:session_failed, :initialization_failed]
    if tree, do: assert_receive({:DOWN, ^monitor, :process, ^tree, _}, 1_000)
  end

  test "a detector completion for audio before a settled native boundary cannot start a new turn" do
    observer = self()
    warmup = :binary.copy(<<0>>, 1_024)

    classify = fn _model, stream, audio ->
      if audio == warmup do
        {:ok, stream, []}
      else
        send(observer, {:classifying, self()})

        receive do
          :continue -> {:ok, stream, [0.9, 0.9, 0.9, 0.9]}
        end
      end
    end

    session = start_session(true, load: fn -> {:ok, :model} end, classify: classify)
    assert_receive {:recognizer, recognizer, _inner}
    _ = event(session, :ready)
    assert :ok = Session.push_audio(session, :binary.copy(<<10, 0>>, 2_048))
    assert_receive {:classifying, worker}
    native = make_ref()
    assert :ok = emit(recognizer, :transcript, turn_ref: native, text: "done")
    _ = event(session, :speech_started)
    _ = event(session, :transcript)

    assert :ok =
             emit(recognizer, :turn_ended,
               turn_ref: native,
               text: "done",
               endpointing: :provider_gap
             )

    _ = event(session, :turn_ended)
    monitor = Process.monitor(worker)
    send(worker, :continue)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}
    refute_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started}}, 200
  end

  test "new turn detector input survives retirement of an older queued inference" do
    observer = self()

    classify = fn _model, stream, audio ->
      if audio == :binary.copy(<<0>>, 1_024) do
        {:ok, stream, []}
      else
        send(observer, {:detector_job, self(), byte_size(audio)})

        receive do
          :continue -> {:ok, stream, [0.9, 0.9, 0.9, 0.9]}
        end
      end
    end

    session = start_session(true, load: fn -> {:ok, :model} end, classify: classify)
    assert_receive {:recognizer, recognizer, _}
    _ = event(session, :ready)
    assert :ok = Session.push_audio(session, :binary.copy(<<1, 0>>, 32_000))
    assert_receive {:detector_job, old_worker, 32_000}

    assert :ok =
             emit(recognizer, :turn_ended,
               turn_ref: make_ref(),
               text: "first",
               endpointing: :provider_gap
             )

    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    _ = event(session, :turn_ended)
    assert :ok = Session.push_audio(session, :binary.copy(<<2, 0>>, 2_048))
    send(old_worker, :continue)
    assert_receive {:detector_job, fresh_worker, 4_096}
    send(fresh_worker, :continue)
    _ = event(session, :speech_started)
    refute_received {:vxpipe_speech, %Event{session: ^session, kind: :speech_started}}
  end

  test "preparation evidence stays retired after adoption instead of gaining new authority" do
    session = start_session(false, [], [sample_rate: 16_000], consumer: nil, lease: self())
    assert_receive {:recognizer, recognizer, _inner}
    assert_receive {:vxpipe_speech_prepared, ^session, _descriptor}, 1_000
    old = make_ref()
    assert :ok = emit(recognizer, :speech_started, turn_ref: old)
    assert :ok = emit(recognizer, :transcript, turn_ref: old, text: "not admitted")
    _ = :sys.get_state(Session.provider(session))
    assert :ok = Session.adopt(session, self())
    _ = event(session, :ready)
    assert :ok = emit(recognizer, :transcript, turn_ref: old, text: "still not admitted")

    assert :ok =
             emit(recognizer, :turn_ended,
               turn_ref: old,
               text: "not admitted",
               endpointing: :provider_gap
             )

    fresh = make_ref()
    assert :ok = emit(recognizer, :transcript, turn_ref: fresh, text: "admitted")
    _ = event(session, :speech_started)
    assert event(session, :transcript).text == "admitted"
  end

  test "interim text retains bounded endpoint protection until actual settlement" do
    session = start_session(false, [], [sample_rate: 16_000], [], boundary_timeout_ms: 100)
    assert_receive {:recognizer, recognizer, _}
    _ = event(session, :ready)
    assert :ok = emit(recognizer, :transcript, turn_ref: make_ref(), text: "unfinished")
    _ = event(session, :speech_started)
    _ = event(session, :transcript)
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
  end

  test "credited frames normalize 48 kHz and decoded Opus only on the detector branch" do
    for codec <- [:linear16, :opus] do
      observer = self()

      classify = fn _model, stream, audio ->
        send(observer, {:detector_pcm, audio})
        {:ok, stream, []}
      end

      session =
        start_session(true, [load: fn -> {:ok, :model} end, classify: classify],
          encoding: codec,
          sample_rate: 48_000
        )

      assert_receive {:recognizer, _pid, _inner}
      _ = event(session, :ready)
      assert_receive {:detector_pcm, warmup}
      assert warmup == :binary.copy(<<0>>, 1_024)
      pcm = :binary.copy(<<3, 0>>, 960)
      payload = if codec == :opus, do: <<1, 2, 3>>, else: pcm

      decoded =
        if codec == :opus,
          do: %{payload: pcm, sample_rate: 48_000, channels: 1, timestamp: 960},
          else: nil

      frame =
        struct!(Vxpipe.CallEngine.Media.AudioFrame,
          tenant_id: "t",
          room_id: "r",
          incarnation_id: "i",
          participant_id: "p",
          connection_id: "c",
          track_id: "a",
          codec: codec,
          sample_rate: 48_000,
          channels: 1,
          sequence_number: 1,
          timestamp: 960,
          received_at: 1,
          payload: payload,
          activity_pcm: decoded
        )

      assert :ok = Session.push_frame(session, frame)
      assert_receive {:recognized_audio, ^payload}
      assert_receive {:detector_pcm, normalized}
      assert normalized == :binary.copy(<<3, 0>>, 320)
      assert :ok = Session.close(session)
    end
  end

  defp start_session(
         vad,
         activity_options \\ [],
         provider_options \\ [sample_rate: 16_000],
         roles \\ [],
         extra_private \\ []
       ) do
    tree = start_supervised!({CapabilityTree, owner: self()}, id: make_ref())
    scope = CapabilityTree.scope(tree)

    assert {:ok, session, :starting} =
             Session.start(
               scope,
               [
                 provider: ConversationalSTT,
                 options: [provider: SpeechOnsetProbe, options: provider_options, vad: vad],
                 private:
                   extra_private ++
                     [
                       recognizer: SpeechOnsetProbe,
                       recognizer_options: provider_options,
                       recognizer_private: [observer: self()],
                       activity_options: activity_options
                     ]
               ] ++ roles
             )

    session
  end

  defp emit(pid, kind, fields), do: GenServer.call(pid, {:emit, kind, fields})

  defp event(session, kind) do
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: ^kind} = event}, 1_000
    assert :ok = Session.ack(session, event)
    event
  end
end
