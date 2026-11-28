defmodule Vxpipe.CallEngine.Speech.ConversationalSTTTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Speech.{CapabilityTree, ConversationalSTT, Event, Session}
  alias Vxpipe.CallEngine.SpeechOnsetProbe

  test "cold model preparation leaves the allocation responsive" do
    parent = self()

    load = fn ->
      send(parent, {:loading, self()})

      receive do
        :finish -> {:ok, :model}
      end
    end

    session =
      start_session(true, load: load, classify: fn _, stream, _ -> {:ok, stream, [0.0]} end)

    assert_receive {:loading, loader}

    try do
      provider = Session.provider(session)
      refute :sys.get_state(provider, 200).ready?
      assert {:error, :busy} = ConversationalSTT.push_audio(provider, :binary.copy(<<0>>, 1024))
      assert %{pending_pcm: "", inference: nil} = :sys.get_state(provider)
    after
      send(loader, :finish)
    end

    _ = event(session, :ready)
  end

  test "a logical timeout for a retired source waits for native settlement" do
    parent = self()

    classifier = fn _, stream, pcm ->
      if pcm == :binary.copy(<<0>>, 1024) do
        {:ok, stream, [0.0]}
      else
        send(parent, {:running, self()})

        receive do
          :finish -> {:ok, stream, [0.9]}
        end
      end
    end

    session = start_session(true, load: fn -> {:ok, :fixture} end, classify: classifier)
    assert_receive {:recognizer, _, _}
    _ = event(session, :ready)
    pcm = :binary.copy(<<1, 0>>, 512)
    assert :ok = Session.push_audio(session, pcm)
    assert_receive {:running, worker}
    provider = Session.provider(session)
    state = :sys.get_state(provider)
    lease = state.runtime.lease

    frame =
      struct(Vxpipe.CallEngine.Media.AudioFrame,
        codec: :linear16,
        channels: 1,
        sample_rate: 16_000,
        payload: pcm,
        timestamp: 2048,
        source_epoch: make_ref()
      )

    :sys.suspend(provider)

    request =
      try do
        req = :gen_server.send_request(provider, {:frame, frame})
        send(lease.pool, {:expired, lease.token, state.inference})
        _ = :sys.get_state(lease.pool)
        req
      after
        :sys.resume(provider)
      end

    assert {:reply, :ok} = :gen_server.receive_response(request, 1000)
    assert %{pending_pcm: ^pcm} = :sys.get_state(provider)
    send(worker, :finish)
    assert_receive {:running, ^worker}
    send(worker, :finish)
  end

  test "caller VAD acquires a node pool lease and retains partial PCM locally" do
    alias Vxpipe.CallEngine.Speech.Silero.Pool
    session = start_session(true, [])
    assert_receive {:recognizer, _, _}
    _ = event(session, :ready)
    assert :ok = Session.push_audio(session, <<1, 0>>)
    state = :sys.get_state(Session.provider(session))
    assert state.runtime.lease.pool == Process.whereis(Pool)
    assert state.pending_pcm == <<1, 0>>
    assert state.inference == nil
    assert state.stream.samples == 0
    assert :ok = Session.close(session)
  end

  test "accepted partial and complete windows reuse the running inference processes" do
    parent = self()

    classify = fn _, stream, pcm ->
      if :binary.first(pcm) == 11, do: send(parent, {:classified_window, stream.samples})
      {:ok, stream, [0.0]}
    end

    session = start_session(true, load: fn -> {:ok, :model} end, classify: classify)
    _ = event(session, :ready)
    provider = Session.provider(session)
    pool = :sys.get_state(provider).runtime.lease.pool
    [worker] = Map.keys(:sys.get_state(pool).workers)
    trace = :trace.session_create(:silero_inference_processes, self(), [])

    try do
      for name <- [:async, :async_nolink, :start_child] do
        :trace.function(trace, {Task.Supervisor, name, :_}, true, [])
      end

      for pid <- [provider, pool, worker], do: :trace.process(trace, pid, true, [:call, :procs])
      assert :ok = Session.push_audio(session, <<11, 0>>)
      assert :ok = Session.push_audio(session, :binary.copy(<<11, 0>>, 1023))
      assert_receive {:classified_window, 0}
      assert_receive {:classified_window, 512}

      for pid <- [provider, pool, worker] do
        ref = :trace.delivered(trace, pid)
        assert_receive {:trace_delivered, ^pid, ^ref}
      end

      refute_received {:trace, _, :spawn, _, _}
      refute_received {:trace, _, :call, {Task.Supervisor, _, _}}
    after
      :trace.session_destroy(trace)
    end
  end

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

  test "optional detector starts before words and owns the turn while speech continues" do
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
    for <<frame::binary-size(1024) <- pcm>>, do: assert_receive({:classified, ^frame})
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

    # Local speech is still confirmed, so the recognizer end is only a segment.
    _ = :sys.get_state(Session.provider(session))
    refute_received {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended}}
    refute_received {:vxpipe_speech, %Event{session: ^session, kind: :speech_started}}
  end

  test "operational offsets and resumed speech retain one turn before any transcript" do
    classify = fn _model, stream, <<sample::little-16, _::binary>> = audio ->
      frames = div(byte_size(audio), 1_024)
      probability = if sample > 0, do: 0.9, else: 0.0
      {:ok, stream, List.duplicate(probability, frames)}
    end

    session = start_session(true, load: fn -> {:ok, :model} end, classify: classify)
    assert_receive {:recognizer, _pid, _inner}
    _ = event(session, :ready)
    voice = :binary.copy(<<1, 0>>, 2_048)
    silence = :binary.copy(<<0, 0>>, 8_192)
    assert :ok = Session.push_audio(session, voice)
    turn = event(session, :speech_started).turn_ref
    assert_receive {:vxpipe_acoustic_activity, ^session, ^turn, :speech_started, onset}, 1_000

    assert :ok = Session.push_audio(session, silence)
    assert_receive {:vxpipe_acoustic_activity, ^session, ^turn, :speech_ended, offset}, 1_000
    assert %{sample_index: 0, sample_rate: 16_000, sequence: 1} = onset
    assert %{sample_index: 2_048, sequence: 2} = offset
    assert offset.at_ms - onset.at_ms == 128

    assert :ok = Session.push_audio(session, voice)
    assert_receive {:vxpipe_acoustic_activity, ^session, ^turn, :speech_started, resumed}, 1_000
    assert %{sample_index: 10_240, sequence: 3} = resumed
    assert resumed.at_ms - offset.at_ms == 512
    refute_received {:vxpipe_speech, %Event{session: ^session, kind: :speech_started}}
  end

  test "confirmed ongoing speech keeps a long utterance open past the orphan timeout" do
    classify = fn _model, stream, audio ->
      {:ok, stream, List.duplicate(0.9, div(byte_size(audio), 1_024))}
    end

    session =
      start_session(
        true,
        [load: fn -> {:ok, :model} end, classify: classify],
        [sample_rate: 16_000],
        [],
        boundary_timeout_ms: 50
      )

    assert_receive {:recognizer, recognizer, _inner}
    _ = event(session, :ready)
    assert :ok = Session.push_audio(session, :binary.copy(<<1, 0>>, 2_048))
    _ = event(session, :speech_started)
    refute_receive {:vxpipe_speech_closed, ^session, _}, 100
    assert :ok = emit(recognizer, :transcript, turn_ref: make_ref(), text: "still speaking")
    _ = event(session, :transcript)
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
        {:ok, stream, [0.0]}
      else
        send(observer, {:classifying, self()})

        receive do
          :continue -> {:ok, stream, [0.9]}
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
    send(worker, :continue)
    _ = :sys.get_state(worker)
    refute_receive {:vxpipe_speech, %Event{session: ^session, kind: :speech_started}}, 200
  end

  test "new turn detector input survives retirement of an older queued inference" do
    observer = self()

    classify = fn _model, stream, audio ->
      if audio == :binary.copy(<<0>>, 1_024) do
        {:ok, stream, [0.0]}
      else
        send(observer, {:detector_job, self(), byte_size(audio)})

        receive do
          :continue -> {:ok, stream, [0.9]}
        end
      end
    end

    session = start_session(true, load: fn -> {:ok, :model} end, classify: classify)
    assert_receive {:recognizer, recognizer, _}
    _ = event(session, :ready)
    assert :ok = Session.push_audio(session, :binary.copy(<<1, 0>>, 32_000))
    assert_receive {:detector_job, old_worker, 1_024}

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

    for _ <- 1..4 do
      assert_receive {:detector_job, fresh_worker, 1_024}
      send(fresh_worker, :continue)
    end

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
        {:ok, stream, [0.0]}
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
      assert :sys.get_state(Session.provider(session)).pending_pcm == :binary.copy(<<3, 0>>, 320)
      refute_received {:detector_pcm, _}
      assert :ok = Session.close(session)
    end
  end

  describe "local VAD turn end" do
    test "silence finalizes the recognizer and its final text ends the turn as a local gap" do
      session = start_local_session(finalize: true)
      assert_receive {:recognizer, recognizer, _inner}
      _ = event(session, :ready)
      assert {:ok, descriptor} = Session.describe(session)
      assert descriptor.endpointing == :local_gap
      refute descriptor.eager_end?

      assert :ok = Session.push_audio(session, voice())
      start = event(session, :speech_started)
      native = make_ref()
      assert :ok = emit(recognizer, :transcript, turn_ref: native, text: "book a table")
      assert event(session, :transcript).text == "book a table"

      assert :ok = Session.push_audio(session, silence())
      assert_receive {:finalize_requested, ^recognizer}, 1_000
      refute_received {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended}}

      assert :ok =
               emit(recognizer, :turn_ended,
                 turn_ref: native,
                 text: "book a table for two",
                 endpointing: :provider_gap
               )

      assert event(session, :transcript).text == "book a table for two"
      ended = event(session, :turn_ended)
      assert ended.turn_ref == start.turn_ref
      assert ended.text == "book a table for two"
      assert ended.endpointing == :local_gap
    end

    test "a provider turn end while the caller still speaks does not end the turn" do
      session = start_local_session(finalize: true)
      assert_receive {:recognizer, recognizer, _inner}
      _ = event(session, :ready)
      assert :ok = Session.push_audio(session, voice())
      start = event(session, :speech_started)
      first = make_ref()

      assert :ok =
               emit(recognizer, :turn_ended,
                 turn_ref: first,
                 text: "I want",
                 endpointing: :provider_gap
               )

      assert event(session, :transcript).text == "I want"
      assert :ok = Session.push_audio(session, voice())
      assert :ok = emit(recognizer, :transcript, turn_ref: make_ref(), text: "a table")
      transcript = event(session, :transcript)
      assert transcript.text == "I want a table"
      assert transcript.turn_ref == start.turn_ref
      _ = :sys.get_state(Session.provider(session))
      refute_received {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended}}
    end

    test "a recognizer without finalization ends with its latest text after a bounded wait" do
      session = start_local_session(finalize: false)
      assert_receive {:recognizer, recognizer, _inner}
      _ = event(session, :ready)
      assert :ok = Session.push_audio(session, voice())
      start = event(session, :speech_started)
      assert :ok = emit(recognizer, :transcript, turn_ref: make_ref(), text: "hello there")
      _ = event(session, :transcript)
      assert :ok = Session.push_audio(session, silence())
      ended = event(session, :turn_ended)
      assert ended.turn_ref == start.turn_ref
      assert ended.text == "hello there"
      assert ended.endpointing == :local_gap
      refute_received {:finalize_requested, _}
    end

    test "speech resuming inside the resume window keeps the turn open" do
      session = start_local_session([finalize: true], endpoint_hangover_ms: 200)
      assert_receive {:recognizer, recognizer, _inner}
      _ = event(session, :ready)
      assert :ok = Session.push_audio(session, voice())
      start = event(session, :speech_started)
      assert :ok = emit(recognizer, :transcript, turn_ref: make_ref(), text: "wait")
      _ = event(session, :transcript)
      assert :ok = Session.push_audio(session, silence())
      assert_receive {:vxpipe_acoustic_activity, ^session, _turn, :speech_ended, _}, 1_000
      assert :ok = Session.push_audio(session, voice())
      assert_receive {:vxpipe_acoustic_activity, ^session, turn, :speech_started, _}, 1_000
      assert turn == start.turn_ref
      refute_receive {:finalize_requested, _}, 300
    end
  end

  defp start_local_session(provider_options, private \\ []) do
    classify = fn _model, stream, <<sample::little-16, _::binary>> = audio ->
      frames = div(byte_size(audio), 1_024)
      probability = if sample > 0, do: 0.9, else: 0.0
      {:ok, stream, List.duplicate(probability, frames)}
    end

    start_session(
      true,
      [load: fn -> {:ok, :model} end, classify: classify],
      [sample_rate: 16_000] ++ provider_options,
      [],
      Keyword.merge([endpoint_hangover_ms: 20, final_wait_ms: 100], private)
    )
  end

  defp voice, do: :binary.copy(<<1, 0>>, 2_048)
  defp silence, do: :binary.copy(<<0, 0>>, 8_192)

  defp start_session(
         vad,
         activity_options \\ [],
         provider_options \\ [sample_rate: 16_000],
         roles \\ [],
         extra_private \\ []
       ) do
    activity_options =
      if vad and Keyword.has_key?(activity_options, :load),
        do: Vxpipe.CallEngine.Speech.SileroPoolFixture.options(__MODULE__, activity_options),
        else: activity_options

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
