defmodule Vxpipe.CallEngine.Speech.DuplexSTSConversationTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Encoder}
  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.Providers.MorseCode.DuplexSTSSession, as: DuplexSTS

  @sample_rate 16_000

  test "clock defaults to realtime, manual is opt-in and an unknown clock is rejected" do
    assert {:ok, descriptor} = DuplexSTS.configure([])
    assert Map.fetch!(descriptor.settings, :clock) == :realtime
    assert {:ok, manual} = DuplexSTS.configure(clock: :manual)
    assert Map.fetch!(manual.settings, :clock) == :manual
    assert {:error, :invalid_configuration} = DuplexSTS.configure(clock: :fast)
  end

  test "advance is rejected while the realtime clock owns the session" do
    %{session: session, provider: provider} = start_session(clock: :realtime)
    assert {:error, :unsupported_operation} = DuplexSTS.advance(provider, 20)
    assert :ok = Session.close(session)
  end

  test "rejects an amplitude that cannot open the gate and plays a low accepted one" do
    assert {:error, :invalid_configuration} = DuplexSTS.configure(amplitude: 1)

    %{session: session, provider: provider} = start_session(clock: :manual, amplitude: 800)
    push_chunks(session, "HI")
    turn = drain_until_turn_ended(session)
    assert {:ok, _output} = Session.admit_output(session, turn)
    assert IO.iodata_to_binary(play_reply(session, provider)) != <<>>
  end

  test "plays every burst when an inter-word gap exceeds the segmenter gap" do
    %{session: session, provider: provider} =
      start_session(clock: :manual, unit_duration_ms: 150)

    push_chunks(session, "AB", unit_duration_ms: 150)
    turn = drain_until_turn_ended(session)
    assert {:ok, _output} = Session.admit_output(session, turn)
    assert IO.iodata_to_binary(play_reply(session, provider)) != <<>>
  end

  test "yielding before admission settles the room output when its admission arrives" do
    %{session: session, provider: provider} = start_session(clock: :manual)
    push_chunks(session, "HI")
    turn = drain_until_turn_ended(session)

    # Talk over the not-yet-admitted reply; the provider yields and remembers it.
    push_chunks(session, "NO")
    drain_until_turn_ended(session)
    advance(provider, 40)

    assert {:ok, _output} = Session.admit_output(session, turn)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :interrupted, turn_ref: ^turn} = event},
                   500

    assert :ok = Session.ack(session, event)
  end

  test "plays two replies queued behind one output, in order" do
    %{session: session, provider: provider} = start_session(clock: :manual, yield?: false)
    push_chunks(session, "HI")
    first = drain_until_turn_ended(session)
    assert {:ok, first_output} = Session.admit_output(session, first)

    push_chunks(session, "NO")
    second = drain_until_turn_ended(session)

    push_chunks(session, "YES")
    third = drain_until_turn_ended(session)

    assert IO.iodata_to_binary(play_reply(session, provider)) != <<>>
    assert :ok = Session.settle_output(session, first_output, 0)

    assert {:ok, second_output} = Session.admit_output(session, second)
    assert IO.iodata_to_binary(play_reply(session, provider)) != <<>>
    assert :ok = Session.settle_output(session, second_output, 0)

    assert {:ok, third_output} = Session.admit_output(session, third)
    assert IO.iodata_to_binary(play_reply(session, provider)) != <<>>
    assert :ok = Session.settle_output(session, third_output, 0)
  end

  test "keeps the reply open and yields when caller tone arrives while a credit is held" do
    %{session: session, provider: provider} = start_session()
    push_chunks(session, "HI")
    turn = drain_until_turn_ended(session)

    assert {:ok, output} = Session.admit_output(session, turn)
    advance(provider, 220)
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = held}

    push_chunks(session, "NO")
    drain_until_turn_ended(session)

    # The provider finishes the interrupted reply only after the held credit.
    assert :ok = Session.validate_audio(session, held)
    assert :ok = Session.ack_audio(session, held)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :output_transcript, turn_ref: ^turn} =
                      transcript}

    assert :ok = Session.ack(session, transcript)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :output_completed, turn_ref: ^turn} = done}

    assert :ok = Session.ack(session, done)
    assert :ok = Session.settle_output(session, output, 0)
  end

  test "discards clock-paced silence before the burst and replays the pre-roll" do
    %{session: session, provider: provider} = start_session()
    push_chunks(session, "HI")
    turn = drain_until_turn_ended(session)

    assert {:ok, _output} = Session.admit_output(session, turn)

    # The 200 ms leading silence is below the activation gate: no burst opens.
    advance(provider, 200)
    refute_received {:vxpipe_speech_audio, %Audio{}}

    until_audio(session, provider)
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = first}
    pre_roll_bytes = div(200 * @sample_rate, 1_000) * 2
    silence = :binary.copy(<<0, 0>>, div(pre_roll_bytes, 2))
    assert :binary.part(first.payload, 0, pre_roll_bytes) == silence
    assert :ok = Session.validate_audio(session, first)
    assert :ok = Session.ack_audio(session, first)

    drain_output(session, provider)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :output_transcript, turn_ref: ^turn} =
                      transcript}

    assert :ok = Session.ack(session, transcript)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :output_completed, turn_ref: ^turn} = done}

    assert :ok = Session.ack(session, done)

    # Silence after the reply is discarded: advancing further emits no new burst.
    advance(provider, 2_000)
    refute_received {:vxpipe_speech_audio, %Audio{}}
    refute_received {:vxpipe_speech, %Event{kind: :output_completed}}
  end

  test "fails the session explicitly when pre-admission output overflows the receive buffer" do
    %{session: session, provider: provider} = start_session()
    push_chunks(session, "HI")
    _turn = drain_until_turn_ended(session)

    # Never admit the output; the provider keeps streaming with no flow control.
    monitor = Process.monitor(provider)
    assert {:error, :buffer_overflow} = DuplexSTS.advance(provider, 8_000)
    assert_receive {:DOWN, ^monitor, :process, ^provider, {:shutdown, :buffer_overflow}}
    _ = session
  end

  # Helpers ------------------------------------------------------------------

  defp start_session(provider_options \\ [clock: :manual]) do
    scope =
      start_supervised!(Supervisor.child_spec({CapabilityTree, owner: self()}, id: make_ref()))

    options = [provider: DuplexSTS, options: provider_options, owner: self()]
    {:ok, session, :starting} = Session.start(CapabilityTree.scope(scope), options)
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}, 1_000
    assert :ok = Session.ack(session, ready)

    %{session: session, provider: Session.provider(session)}
  end

  defp push_chunks(session, text, encode_options \\ []) do
    {:ok, pcm} = encode(text, encode_options)

    for <<chunk::binary-size(320) <- pcm>> do
      assert :ok = Session.push_audio(session, chunk)
    end

    remainder = rem(byte_size(pcm), 320)

    if remainder > 0 do
      <<_::binary-size(byte_size(pcm) - remainder), tail::binary>> = pcm
      assert :ok = Session.push_audio(session, tail)
    end
  end

  defp drain_until_turn_ended(session) do
    receive do
      {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended, turn_ref: turn} = event} ->
        assert :ok = Session.ack(session, event)
        turn

      {:vxpipe_speech, %Event{session: ^session} = event} ->
        assert :ok = Session.ack(session, event)
        drain_until_turn_ended(session)
    after
      1_000 -> flunk("no turn_ended event")
    end
  end

  defp until_audio(session, provider), do: until_audio(session, provider, 500)

  defp until_audio(_session, _provider, 0), do: flunk("no output audio")

  defp until_audio(session, provider, remaining) do
    receive do
      {:vxpipe_speech_audio, %Audio{session: ^session} = audio} ->
        send(self(), {:vxpipe_speech_audio, audio})
        :ok
    after
      0 ->
        advance(provider, 20)
        until_audio(session, provider, remaining - 1)
    end
  end

  defp drain_output(session, provider, remaining \\ 1_000)

  defp drain_output(_session, _provider, 0), do: flunk("output did not settle")

  defp drain_output(session, provider, remaining) do
    receive do
      {:vxpipe_speech_audio, %Audio{session: ^session} = audio} ->
        assert :ok = Session.validate_audio(session, audio)
        assert :ok = Session.ack_audio(session, audio)
        drain_output(session, provider, remaining)

      {:vxpipe_speech, %Event{session: ^session, kind: kind} = event}
      when kind in [:output_transcript, :output_completed] ->
        send(self(), {:vxpipe_speech, event})
        :ok
    after
      0 ->
        advance(provider, 20)
        drain_output(session, provider, remaining - 1)
    end
  end

  defp advance(provider, ms), do: :ok = DuplexSTS.advance(provider, ms)

  # Drive the manual clock, ack every chunk, and return the played payloads in
  # order once the output completes.
  defp play_reply(session, provider, collected \\ [], remaining \\ 2_000)

  defp play_reply(_session, _provider, _collected, 0), do: flunk("output did not complete")

  defp play_reply(session, provider, collected, remaining) do
    receive do
      {:vxpipe_speech_audio, %Audio{session: ^session} = audio} ->
        assert :ok = Session.validate_audio(session, audio)
        assert :ok = Session.ack_audio(session, audio)
        play_reply(session, provider, [audio.payload | collected], remaining)

      {:vxpipe_speech, %Event{session: ^session, kind: :output_transcript} = event} ->
        assert :ok = Session.ack(session, event)
        play_reply(session, provider, collected, remaining)

      {:vxpipe_speech, %Event{session: ^session, kind: :output_completed} = event} ->
        assert :ok = Session.ack(session, event)
        Enum.reverse(collected)
    after
      0 ->
        advance(provider, 20)
        play_reply(session, provider, collected, remaining - 1)
    end
  end

  defp encode(text, options) do
    {:ok, config} = Config.new(options)
    Encoder.encode(config, text)
  end
end
