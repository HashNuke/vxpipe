defmodule Vxpipe.Providers.ElevenLabs.STTSessionTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Descriptor, Event, Session, Silero}
  alias Vxpipe.CallEngine.TestElevenLabsScribeTransport, as: Wire
  alias Vxpipe.Providers.ElevenLabs.{Scribe, STTSession}

  test "configuration advertises local acoustic authority without optional or STS claims" do
    assert {:ok, descriptor} = STTSession.configure([])
    assert :ok = Descriptor.validate_conversational_stt(descriptor)
    assert descriptor.endpointing == :local_gap and descriptor.speech_start?
    refute descriptor.eager_end? or descriptor.resume? or descriptor.finite_input?
    assert descriptor.usage_identity.model == "scribe_v2_realtime"

    for options <- [[api_key: "secret"], [commit_strategy: :invalid], [sample_rate: 8_000]] do
      assert {:error, :invalid_configuration} = STTSession.configure(options)
    end
  end

  test "an empty initial partial does not invent activity or retire the ready recognizer" do
    {session, wire} = start_session()
    ready(session, wire)
    Wire.deliver(wire, {:partial, ""})
    _ = :sys.get_state(Session.provider(session))
    refute_received {:vxpipe_speech, %Event{kind: :speech_started}}
    refute_received {:vxpipe_speech_closed, ^session, _reason}
    assert :ok = Session.push_audio(session, voice())
    assert %Event{kind: :speech_started} = next_event(session)
  end

  test "onset precedes recognition and turn end waits for the outstanding manual commit" do
    {session, wire} = start_session()
    refute_receive {:vxpipe_speech, %Event{kind: :ready}}, 20
    ready(session, wire)
    assert :ok = Session.push_audio(session, voice())
    assert %Event{kind: :speech_started, turn_ref: turn} = next_event(session)
    assert_receive {:scribe_audio, ^wire, _audio}
    Wire.deliver(wire, {:partial, "FIRST"})
    assert %Event{kind: :transcript, turn_ref: ^turn, text: "FIRST"} = next_event(session)
    endpoint(session, wire)
    refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
    Wire.deliver(wire, {:segment, "FIRST FINAL"})
    assert %Event{kind: :transcript, turn_ref: ^turn, text: "FIRST FINAL"} = next_event(session)

    assert %Event{
             kind: :turn_ended,
             turn_ref: ^turn,
             text: "FIRST FINAL",
             endpointing: :local_gap,
             audio_duration_ms: 128
           } = next_event(session)
  end

  test "manual turns reuse one socket while older recognition settles without exchanging transcripts" do
    {session, wire} = start_session()
    ready(session, wire)
    first_audio = voice()
    second_audio = :binary.copy(<<2, 0>>, 2_048)
    assert :ok = Session.push_audio(session, first_audio)
    assert %Event{kind: :speech_started, turn_ref: first} = next_event(session)
    assert_receive {:scribe_audio, ^wire, ^first_audio}, 1_000
    endpoint(session, wire)
    assert_receive {:scribe_audio, ^wire, tail}, 1_000
    assert tail == :binary.copy(<<0, 0>>, 8_192)
    refute_received {:scribe_audio, ^wire, _stale}
    assert :ok = Session.push_audio(session, second_audio)
    assert %Event{kind: :speech_started, turn_ref: second} = next_event(session)
    refute first == second
    await_input(session)
    refute_receive {:scribe_audio, ^wire, _withheld}, 100
    Wire.deliver(wire, {:partial, "OLDER"})
    assert %Event{kind: :transcript, turn_ref: ^first, text: "OLDER"} = next_event(session)
    Wire.deliver(wire, {:segment, "OLDER FINAL"})
    assert %Event{kind: :transcript, turn_ref: ^first} = next_event(session)
    assert %Event{kind: :turn_ended, turn_ref: ^first} = next_event(session)
    assert_receive {:scribe_audio, ^wire, ^second_audio}, 1_000
    refute_received {:scribe_started, _replacement}
    Wire.deliver(wire, {:partial, "NEWER"})
    assert %Event{kind: :transcript, turn_ref: ^second, text: "NEWER"} = next_event(session)
    endpoint(session, wire)
    Wire.deliver(wire, {:segment, "NEWER FINAL"})
    assert %Event{kind: :transcript, turn_ref: ^second, text: "NEWER FINAL"} = next_event(session)
    assert %Event{kind: :turn_ended, turn_ref: ^second, text: "NEWER FINAL"} = next_event(session)
  end

  test "committed segment without an outstanding manual commit fails closed" do
    {session, wire} = start_session()
    ready(session, wire)
    assert :ok = Session.push_audio(session, voice())
    assert %Event{kind: :speech_started} = next_event(session)
    assert_receive {:scribe_audio, ^wire, _audio}, 1_000
    monitor = Process.monitor(wire)
    Wire.deliver(wire, {:segment, "UNCOMMITTED"})
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^wire, _reason}, 1_000
    refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
  end

  test "model preparation gates readiness and cancellation retires private execution" do
    observer = self()

    {session, wire} =
      start_session(
        load: fn ->
          send(observer, {:loading_scribe_model, self()})
          receive do: (:continue -> {:ok, :model})
        end
      )

    assert_receive {:loading_scribe_model, worker}, 1_000
    Wire.deliver(wire, {:ready, "synthetic-request"})
    _ = :sys.get_state(Session.provider(session))
    refute_received {:vxpipe_speech, %Event{kind: :ready}}
    worker_monitor = Process.monitor(worker)
    wire_monitor = Process.monitor(wire)
    assert :ok = Session.close(session)
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, _reason}, 1_000
    assert_receive {:DOWN, ^wire_monitor, :process, ^wire, _reason}, 1_000
  end

  test "missing commit settlement fails without fabricating final recognition" do
    {session, wire} = start_session()
    ready(session, wire)
    assert :ok = Session.push_audio(session, voice())
    assert %Event{kind: :speech_started} = next_event(session)
    endpoint(session, wire)
    monitor = Process.monitor(wire)
    send(Session.provider(session), :commit_timeout)
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^wire, _reason}, 1_000
    refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
  end

  test "inference admission bounds queued PCM and hard provider death retires its worker" do
    observer = self()

    {session, wire} =
      start_session(
        classify: fn model, stream, audio ->
          send(observer, {:scribe_classifying, self()})
          receive do: (:continue -> classify(model, stream, audio))
        end
      )

    ready(session, wire)
    assert :ok = Session.push_audio(session, voice())
    assert_receive {:scribe_classifying, worker}, 1_000
    assert :ok = Session.push_audio(session, voice())
    for _ <- 1..2, do: assert(:ok = Session.push_audio(session, :binary.copy(<<1, 0>>, 16_000)))
    assert {:error, :busy} = Session.push_audio(session, :binary.copy(<<1, 0>>, 16_000))
    refute_received {:vxpipe_speech, %Event{kind: :speech_started}}
    monitor = Process.monitor(worker)
    wire_monitor = Process.monitor(wire)
    Process.exit(Session.provider(session), :kill)
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}, 1_000
    assert_receive {:DOWN, ^wire_monitor, :process, ^wire, _reason}, 1_000
  end

  test "audio arriving during classification is accepted in order within the PCM budget" do
    observer = self()
    first = voice()
    second = :binary.copy(<<2, 0>>, 2_048)

    {session, wire} =
      start_session(
        classify: fn model, stream, audio ->
          send(observer, {:queued_scribe_classifying, self(), audio})
          receive do: (:continue -> classify(model, stream, audio))
        end
      )

    ready(session, wire)
    assert :ok = Session.push_audio(session, first)
    assert_receive {:queued_scribe_classifying, worker, ^first}, 1_000
    assert :ok = Session.push_audio(session, second)
    refute_received {:vxpipe_speech, %Event{kind: :speech_started}}
    send(worker, :continue)
    assert %Event{kind: :speech_started} = next_event(session)
    assert_receive {:scribe_audio, ^wire, ^first}, 1_000
    assert_receive {:queued_scribe_classifying, next_worker, ^second}, 1_000
    send(next_worker, :continue)
    assert_receive {:scribe_audio, ^wire, ^second}, 1_000
    await_input(session)
    refute_received {:vxpipe_speech_closed, ^session, _reason}
  end

  test "queued audio is bounded while a completed acoustic turn awaits recognition" do
    {session, wire} = start_session()
    ready(session, wire)
    assert :ok = Session.push_audio(session, voice())
    assert %Event{kind: :speech_started} = next_event(session)
    endpoint(session, wire)
    assert :ok = Session.push_audio(session, voice())
    assert %Event{kind: :speech_started} = next_event(session)
    await_input(session)
    audio = :binary.copy(<<1, 0>>, 16_000)

    for _ <- 1..2 do
      assert :ok = Session.push_audio(session, audio)
      await_input(session)
    end

    assert {:error, :busy} = Session.push_audio(session, audio)
    refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
  end

  test "a twenty-second segment commit preserves the acoustic turn until its later endpoint" do
    {session, wire} = start_session()
    ready(session, wire)

    for _ <- 1..20 do
      assert :ok = Session.push_audio(session, :binary.copy(<<1, 0>>, 16_000))
      await_input(session)
    end

    assert %Event{kind: :speech_started, turn_ref: turn} = next_event(session)
    assert_receive {:scribe_commit, ^wire}
    Wire.deliver(wire, {:segment, "PREFIX"})
    assert %Event{kind: :transcript, turn_ref: ^turn, text: "PREFIX"} = next_event(session)
    refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
    endpoint(session, wire)
    Wire.deliver(wire, {:segment, "SUFFIX"})
    assert %Event{kind: :transcript, turn_ref: ^turn, text: "PREFIX SUFFIX"} = next_event(session)
    assert %Event{kind: :turn_ended, turn_ref: ^turn, text: "PREFIX SUFFIX"} = next_event(session)
  end

  test "wire-level twenty-second budget counts preceding idle alongside voice" do
    {session, wire} = start_session()
    ready(session, wire)

    for _ <- 1..10 do
      assert :ok = Session.push_audio(session, :binary.copy(<<0, 0>>, 16_000))
      await_input(session)
    end

    refute_received {:vxpipe_speech, %Event{kind: :speech_started}}

    for _ <- 1..11 do
      assert :ok = Session.push_audio(session, :binary.copy(<<1, 0>>, 16_000))
      await_input(session)
    end

    assert %Event{kind: :speech_started, turn_ref: turn} = next_event(session)
    assert_receive {:scribe_commit, ^wire}, 1_000
    Wire.deliver(wire, {:segment, "PREFIX"})
    assert %Event{kind: :transcript, turn_ref: ^turn, text: "PREFIX"} = next_event(session)
    refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
    unaligned_endpoint(session, wire)
    Wire.deliver(wire, {:segment, "SUFFIX"})
    assert %Event{kind: :transcript, turn_ref: ^turn, text: "PREFIX SUFFIX"} = next_event(session)
    assert %Event{kind: :turn_ended, turn_ref: ^turn, text: "PREFIX SUFFIX"} = next_event(session)
  end

  test "real silent PCM beyond thirty-six seconds settles through explicit idle commits" do
    {session, wire} = start_session()
    ready(session, wire)
    monitor = Process.monitor(wire)
    silence = :binary.copy(<<0, 0>>, 16_000)

    for _ <- 1..21 do
      assert :ok = Session.push_audio(session, silence)
      await_input(session)
    end

    assert_receive {:scribe_commit, ^wire}, 1_000
    first_epoch = drain_audio(wire)
    assert byte_size(first_epoch) == 640_000
    refute_received {:vxpipe_speech, %Event{}}
    Wire.deliver(wire, {:segment, ""})
    _ = :sys.get_state(Session.provider(session))

    for _ <- 1..20 do
      assert :ok = Session.push_audio(session, silence)
      await_input(session)
    end

    assert_receive {:scribe_commit, ^wire}, 1_000
    second_epoch = drain_audio(wire)
    assert byte_size(second_epoch) == 640_000
    refute_received {:vxpipe_speech, %Event{}}
    Wire.deliver(wire, {:segment, ""})
    _ = :sys.get_state(Session.provider(session))

    refute_received {:vxpipe_speech, %Event{}}
    refute_received {:vxpipe_speech_closed, ^session, _reason}
    refute_received {:DOWN, ^monitor, :process, ^wire, _reason}

    wire_audio = drain_audio(wire)

    assert %{input: %{pre_roll: retained, pending: pending}} =
             :sys.get_state(Session.provider(session))

    assert first_epoch <> second_epoch <> wire_audio <> retained <> pending ==
             :binary.copy(<<0>>, 41 * 32_000)
  end

  test "acoustic input queues while an idle commit awaits its empty acknowledgement" do
    {session, wire} = start_session()
    ready(session, wire)
    silence = :binary.copy(<<0, 0>>, 16_000)

    for _ <- 1..21 do
      assert :ok = Session.push_audio(session, silence)
      await_input(session)
    end

    assert_receive {:scribe_commit, ^wire}, 1_000
    assert byte_size(drain_audio(wire)) == 640_000
    assert :ok = Session.push_audio(session, voice())
    await_input(session)
    assert %Event{kind: :speech_started, turn_ref: turn} = next_event(session)
    assert drain_audio(wire) == ""
    refute_received {:scribe_audio, ^wire, _withheld}
    refute_received {:scribe_commit, ^wire}

    Wire.deliver(wire, {:segment, ""})
    _ = :sys.get_state(Session.provider(session))
    assert_receive {:scribe_audio, ^wire, _flushed}, 1_000
    refute_received {:vxpipe_speech, %Event{kind: :transcript}}
    unaligned_endpoint(session, wire)
    Wire.deliver(wire, {:segment, "QUEUED YES"})
    assert %Event{kind: :transcript, turn_ref: ^turn, text: "QUEUED YES"} = next_event(session)
    assert %Event{kind: :turn_ended, turn_ref: ^turn, text: "QUEUED YES"} = next_event(session)
  end

  test "idle commit inherits the bounded queue and commit deadline without fabricating turns" do
    {session, wire} = start_session()
    ready(session, wire)
    monitor = Process.monitor(wire)
    silence = :binary.copy(<<0, 0>>, 16_000)

    for _ <- 1..21 do
      assert :ok = Session.push_audio(session, silence)
      await_input(session)
    end

    assert_receive {:scribe_commit, ^wire}, 1_000
    _ = :sys.get_state(Session.provider(session))

    assert :ok = Session.push_audio(session, silence)
    await_input(session)
    assert :ok = Session.push_audio(session, silence)
    await_input(session)
    assert {:error, :busy} = Session.push_audio(session, silence)
    refute_received {:vxpipe_speech, %Event{}}

    %{commit_ref: ref} = :sys.get_state(Session.provider(session))
    send(Session.provider(session), {:commit_timeout, ref})
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^wire, _reason}, 1_000
    refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
  end

  test "unexpected recognized speech during an idle commit fails closed without attaching a turn" do
    {session, wire} = start_session()
    ready(session, wire)
    monitor = Process.monitor(wire)
    silence = :binary.copy(<<0, 0>>, 16_000)

    for _ <- 1..21 do
      assert :ok = Session.push_audio(session, silence)
      await_input(session)
    end

    assert_receive {:scribe_commit, ^wire}, 1_000
    Wire.deliver(wire, {:segment, "PHANTOM"})
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^wire, _reason}, 1_000
    refute_received {:vxpipe_speech, %Event{kind: :transcript}}
    refute_received {:vxpipe_speech, %Event{kind: :turn_ended}}
  end

  test "a queued turn counts the prior turn's trailing silence in its wire epoch" do
    {session, wire} = start_session()
    ready(session, wire)
    assert :ok = Session.push_audio(session, voice())
    assert %Event{kind: :speech_started, turn_ref: first} = next_event(session)
    endpoint(session, wire)

    for _ <- 1..2 do
      assert :ok = Session.push_audio(session, :binary.copy(<<0>>, 32_000))
      await_input(session)
    end

    assert :ok = Session.push_audio(session, voice())
    await_input(session)
    assert %Event{kind: :speech_started, turn_ref: second} = next_event(session)
    _prior_epoch = drain_audio(wire)
    Wire.deliver(wire, {:segment, "FIRST"})
    assert %Event{kind: :transcript, turn_ref: ^first} = next_event(session)
    assert %Event{kind: :turn_ended, turn_ref: ^first} = next_event(session)

    for _ <- 1..18 do
      assert :ok = Session.push_audio(session, :binary.copy(<<1, 0>>, 16_000))
      await_input(session)
    end

    assert_receive {:scribe_commit, ^wire}, 1_000
    assert byte_size(drain_audio(wire)) == 640_000
    Wire.deliver(wire, {:segment, "SECOND"})
    assert %Event{kind: :transcript, turn_ref: ^second, text: "SECOND"} = next_event(session)
    unaligned_endpoint(session, wire)
    Wire.deliver(wire, {:segment, "END"})
    assert %Event{kind: :transcript, turn_ref: ^second, text: "SECOND END"} = next_event(session)
    assert %Event{kind: :turn_ended, turn_ref: ^second, text: "SECOND END"} = next_event(session)
  end

  test "persistent wire preserves the real PCM timeline across two turns with intervening silence" do
    {session, wire} = start_session()
    ready(session, wire)
    monitor = Process.monitor(wire)

    initial = :binary.copy(<<0, 0>>, 4_096)
    first_voice = voice()
    end_first = :binary.copy(<<0, 0>>, 8_192)
    gap_total = :binary.copy(<<0, 0>>, 3_072)
    second_voice = :binary.copy(<<2, 0>>, 2_048)
    filler = :binary.copy(<<1, 0>>, 10_752)
    end_second = :binary.copy(<<0, 0>>, 8_192)
    extra_idle = :binary.copy(<<0, 0>>, 2_048)

    real_input = initial <> first_voice <> end_first <> gap_total <> second_voice
    real_input = real_input <> filler <> filler <> filler <> end_second <> extra_idle

    assert :ok = Session.push_audio(session, initial)
    await_input(session)
    assert :ok = Session.push_audio(session, first_voice)
    await_input(session)
    assert %Event{kind: :speech_started, turn_ref: first} = next_event(session)
    sent_first = drain_audio(wire)

    assert :ok = Session.push_audio(session, end_first)
    await_input(session)
    assert_receive {:scribe_commit, ^wire}, 1_000
    refute_received {:scribe_started, _replacement}
    sent_end_first = drain_audio(wire)

    assert :ok = Session.push_audio(session, gap_total)
    await_input(session)
    assert :ok = Session.push_audio(session, second_voice)
    await_input(session)
    assert %Event{kind: :speech_started, turn_ref: second} = next_event(session)
    refute first == second

    assert drain_audio(wire) == ""
    refute_received {:scribe_audio, ^wire, _withheld}

    for _ <- 1..3 do
      assert :ok = Session.push_audio(session, filler)
      await_input(session)
    end

    assert drain_audio(wire) == ""
    refute_received {:scribe_audio, ^wire, _withheld}
    assert {:error, :busy} = Session.push_audio(session, filler)

    assert :ok = Session.push_audio(session, end_second)
    await_input(session)
    assert :ok = Session.push_audio(session, extra_idle)
    await_input(session)
    assert drain_audio(wire) == ""
    refute_received {:scribe_audio, ^wire, _withheld}
    refute_received {:scribe_commit, ^wire}

    Wire.deliver(wire, {:segment, "FIRST FINAL"})
    assert %Event{kind: :transcript, turn_ref: ^first, text: "FIRST FINAL"} = next_event(session)
    assert %Event{kind: :turn_ended, turn_ref: ^first, text: "FIRST FINAL"} = next_event(session)
    _ = :sys.get_state(Session.provider(session))

    flushed_second = drain_audio(wire)
    assert flushed_second == gap_total <> second_voice <> filler <> filler <> filler <> end_second
    refute_received {:scribe_audio, ^wire, _early_idle}

    assert_receive {:scribe_commit, ^wire}, 1_000
    Wire.deliver(wire, {:segment, "SECOND FINAL"})

    assert %Event{kind: :transcript, turn_ref: ^second, text: "SECOND FINAL"} =
             next_event(session)

    assert %Event{kind: :turn_ended, turn_ref: ^second, text: "SECOND FINAL"} =
             next_event(session)

    _ = :sys.get_state(Session.provider(session))

    flushed_idle = drain_audio(wire)
    # The 8-frame trailing silence emits 5 frames once they fall out of the
    # 3-frame pre-roll; the final 3 frames stay retained for a future onset,
    # so they are preserved in the detector, not stripped.
    assert flushed_idle == binary_part(extra_idle, 0, byte_size(extra_idle) - 3_072)
    assert %{input: %{pre_roll: retained}} = :sys.get_state(Session.provider(session))
    assert retained == binary_part(extra_idle, byte_size(extra_idle) - 3_072, 3_072)

    refute_received {:scribe_started, _replacement}
    refute_received {:DOWN, ^monitor, :process, ^wire, _reason}

    # Full timeline reconstruction: every real input byte reaches the single
    # socket exactly once, in order, with no synthetic padding. Bytes still
    # retained in pre-roll for a future onset are accounted, not lost.
    all_wire = sent_first <> sent_end_first <> flushed_second <> flushed_idle
    assert all_wire <> retained == real_input
  end

  test "packaged acoustic inference drives the session from the existing public PCM fixture" do
    {session, wire} =
      start_session(
        load: &Silero.ModelCache.fetch/0,
        classify: &Silero.push(&2, &1, &3)
      )

    ready(session, wire)
    audio = File.read!(Vxpipe.Providers.Deepgram.LiveFixture.pcm_path())

    for chunk <- chunks(audio) do
      assert :ok = Session.push_audio(session, chunk)
      await_input(session)
    end

    assert %Event{kind: :speech_started, turn_ref: turn} = next_event(session)
    assert_receive {:scribe_commit, ^wire}
    Wire.deliver(wire, {:segment, "PUBLIC SAMPLE"})
    assert %Event{kind: :transcript, turn_ref: ^turn} = next_event(session)

    assert %Event{
             kind: :turn_ended,
             turn_ref: ^turn,
             endpointing: :local_gap,
             audio_duration_ms: duration
           } = next_event(session)

    assert duration > 0 and duration < div(byte_size(audio), 32)

    refute inspect(:sys.get_status(Session.provider(session)), limit: :infinity) =~
             "synthetic-key"
  end

  defp chunks(""), do: []

  defp chunks(audio) do
    size = min(byte_size(audio), 32_000)
    <<chunk::binary-size(size), rest::binary>> = audio
    [chunk | chunks(rest)]
  end

  defp await_input(session),
    do: await_input(Session.provider(session), System.monotonic_time(:millisecond) + 5_000)

  defp await_input(provider, deadline) do
    assert System.monotonic_time(:millisecond) < deadline,
           "accepted classification did not settle"

    case :sys.get_state(provider) do
      %{inference_ref: nil} -> :ok
      _pending -> await_input(provider, deadline)
    end
  end

  defp voice, do: :binary.copy(<<1, 0>>, 2_048)

  defp drain_audio(wire), do: drain_audio(wire, "")

  defp drain_audio(wire, acc) do
    receive do
      {:scribe_audio, ^wire, audio} -> drain_audio(wire, acc <> audio)
    after
      0 -> acc
    end
  end

  defp unaligned_endpoint(session, wire) do
    assert :ok = Session.push_audio(session, :binary.copy(<<0>>, 18_432))
    assert_receive {:scribe_commit, ^wire}, 1_000
  end

  defp endpoint(session, wire) do
    assert :ok = Session.push_audio(session, :binary.copy(<<0, 0>>, 8_192))
    assert_receive {:scribe_commit, ^wire}, 1_000
  end

  defp start_session(options \\ []) do
    tree = start_supervised!({CapabilityTree, owner: self()})
    assert {:ok, config} = Scribe.new(api_key: "synthetic-key")
    activity = Keyword.merge([load: fn -> {:ok, :model} end, classify: &classify/3], options)

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: STTSession,
               options: [],
               private: [
                 config: config,
                 wire_module: Wire,
                 wire_options: [observer: self()],
                 activity_options: activity
               ]
             )

    assert_receive {:scribe_started, wire}, 1_000
    {session, wire}
  end

  defp classify(_model, %Silero{} = stream, audio) do
    combined = stream.pending <> audio
    frames = div(byte_size(combined), 1_024)
    <<complete::binary-size(frames * 1_024), pending::binary>> = combined

    probabilities =
      for <<frame::binary-size(1_024) <- complete>>,
        do: if(frame == :binary.copy(<<0>>, 1_024), do: 0.1, else: 0.8)

    {:ok, %Silero{stream | samples: stream.samples + frames * 512, pending: pending},
     probabilities}
  end

  defp ready(session, wire) do
    Wire.deliver(wire, {:ready, "synthetic-request"})
    assert %Event{kind: :ready} = next_event(session)
  end

  defp next_event(session) do
    assert_receive {:vxpipe_speech, event}, 1_000
    assert :ok = Session.ack(session, event)
    event
  end
end
