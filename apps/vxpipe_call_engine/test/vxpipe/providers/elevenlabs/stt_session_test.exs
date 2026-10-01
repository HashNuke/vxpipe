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

    for options <- [[api_key: "secret"], [commit_strategy: :vad], [sample_rate: 8_000]] do
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

  test "new activity starts while an older recognition settles without exchanging transcripts" do
    {session, wire} = start_session()
    ready(session, wire)
    assert :ok = Session.push_audio(session, voice())
    assert %Event{kind: :speech_started, turn_ref: first} = next_event(session)
    endpoint(session, wire)
    assert :ok = Session.push_audio(session, voice())
    assert %Event{kind: :speech_started, turn_ref: second} = next_event(session)
    refute first == second
    Wire.deliver(wire, {:partial, "OLDER"})
    assert %Event{kind: :transcript, turn_ref: ^first, text: "OLDER"} = next_event(session)
    Wire.deliver(wire, {:segment, "OLDER FINAL"})
    assert %Event{kind: :transcript, turn_ref: ^first} = next_event(session)
    assert %Event{kind: :turn_ended, turn_ref: ^first} = next_event(session)
    assert_receive {:scribe_started, next_wire}, 1_000
    refute next_wire == wire
    Wire.deliver(next_wire, {:ready, "next-synthetic-request"})
    _ = :sys.get_state(Session.provider(session))
    Wire.deliver(next_wire, {:partial, "NEWER"})
    assert %Event{kind: :transcript, turn_ref: ^second, text: "NEWER"} = next_event(session)
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

  test "inference admission rejects busy input and hard provider death retires its worker" do
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
    assert {:error, :busy} = Session.push_audio(session, voice())
    refute_received {:vxpipe_speech, %Event{kind: :speech_started}}
    monitor = Process.monitor(worker)
    wire_monitor = Process.monitor(wire)
    Process.exit(Session.provider(session), :kill)
    assert_receive {:vxpipe_speech_closed, ^session, :session_failed}, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}, 1_000
    assert_receive {:DOWN, ^wire_monitor, :process, ^wire, _reason}, 1_000
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
