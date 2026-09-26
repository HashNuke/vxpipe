defmodule Vxpipe.CallEngine.Speech.DuplexSTSConversationTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Encoder}
  alias Vxpipe.CallEngine.Provider.MorseCodeDuplex.Output
  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.Providers.MorseCode.DuplexSTSSession, as: DuplexSTS

  @sample_rate 16_000

  test "clock defaults to realtime, manual is opt-in and an unknown clock is rejected" do
    assert {:ok, descriptor} = DuplexSTS.configure([])
    assert Map.fetch!(descriptor.settings, :clock) == :realtime
    assert descriptor.response_start?
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
    {payloads, _turns} = drive(session, provider)
    assert IO.iodata_to_binary(payloads) != <<>>
  end

  test "plays every burst of one reply as its own admitted response" do
    %{session: session, provider: provider} = start_session(clock: :manual, unit_duration_ms: 150)

    push_chunks(session, "AB", unit_duration_ms: 150)
    {payloads, turns} = drive(session, provider)

    assert length(turns) >= 2
    assert length(Enum.uniq(turns)) == length(turns)
    assert IO.iodata_to_binary(payloads) != <<>>
  end

  test "yielding an announced burst before admission completes it with nothing played" do
    %{session: session, provider: provider} = start_session(clock: :manual)
    push_chunks(session, "HI")
    turn = await_response_started(session, provider)

    # Caller tone arrives while the burst is announced but not yet admitted.
    push_chunks(session, "NO")
    drain_events(session)

    assert {:ok, output} = Session.admit_output(session, turn)

    assert_receive {:vxpipe_speech,
                    %Event{session: ^session, kind: :interrupted, turn_ref: ^turn} = interrupted},
                   500

    assert :ok = Session.ack(session, interrupted)

    assert_receive {:vxpipe_speech,
                    %Event{
                      session: ^session,
                      kind: :output_completed,
                      turn_ref: ^turn,
                      request_ref: reference
                    } = completed},
                   500

    assert reference == output.ref
    assert :ok = Session.ack(session, completed)
    assert :ok = Session.settle_output(session, output, 0)

    # The next reply's burst is admitted and plays.
    push_chunks(session, "YES")
    {payloads, _turns} = drive(session, provider)
    assert IO.iodata_to_binary(payloads) != <<>>
  end

  test "a tool result appends a reply to the output timeline without a turn_ended" do
    %{session: session, provider: provider} = start_session(clock: :manual)

    assert :ok = Session.push_text(session, "TOOL echo {}", response_context: make_ref())
    call_ref = drain_until_tool_call(session)

    assert :ok = DuplexSTS.send_tool_result(provider, call_ref, %{})

    {payloads, turns} = drive(session, provider)

    assert IO.iodata_to_binary(payloads) != <<>>
    assert turns != []

    # No reply announces its own turn_ended; only the caller text turn did.
    receive do
      {:vxpipe_speech, %Event{session: ^session, kind: :turn_ended, turn_ref: turn}} ->
        refute turn in turns
    after
      0 -> :ok
    end
  end

  test "discards clock-paced silence before the burst and replays the pre-roll" do
    %{session: session, provider: provider} = start_session(clock: :manual)
    push_chunks(session, "HI")
    turn = await_response_started(session, provider)
    assert {:ok, output} = Session.admit_output(session, turn)

    until_audio(session, provider)
    assert_receive {:vxpipe_speech_audio, %Audio{session: ^session} = first}
    pre_roll_bytes = div(200 * @sample_rate, 1_000) * 2
    silence = :binary.copy(<<0, 0>>, div(pre_roll_bytes, 2))
    assert :binary.part(first.payload, 0, pre_roll_bytes) == silence
    assert :ok = Session.validate_audio(session, first)
    assert :ok = Session.ack_audio(session, first)

    {_payloads, _turns} = drive(session, provider)
    _ = output

    # Silence after the reply is discarded: advancing further emits no new burst.
    advance(provider, 2_000)
    refute_received {:vxpipe_speech_audio, %Audio{}}
    refute_received {:vxpipe_speech, %Event{kind: :response_started}}
  end

  test "fails the session explicitly when pre-admission output overflows the receive buffer" do
    %{session: session, provider: provider} = start_session(clock: :manual)
    push_chunks(session, "HI")
    _turn = await_response_started(session, provider)

    # Never admit the output; the provider keeps streaming with no flow control.
    monitor = Process.monitor(provider)
    assert {:error, :buffer_overflow} = DuplexSTS.advance(provider, 8_000)
    assert_receive {:DOWN, ^monitor, :process, ^provider, {:shutdown, :buffer_overflow}}
    _ = session
  end

  test "fails explicitly when more replies queue than the FIFO allows" do
    %{session: session, provider: provider} = start_session(clock: :manual, yield?: false)
    push_chunks(session, "HI")
    _turn = await_response_started(session, provider)
    monitor = Process.monitor(provider)
    context = make_ref()

    result =
      Enum.reduce_while(~c"ABCDEFGHIJKLMNOPQRSTUVWXYZ", :ok, fn char, :ok ->
        case submit_text_turn(session, <<char>>, context) do
          :ok -> {:cont, :ok}
          {:error, _reason} = error -> {:halt, error}
        end
      end)

    assert result in [{:error, :pending_reply_overflow}, {:error, :closed}]
    assert_receive {:DOWN, ^monitor, :process, ^provider, {:shutdown, :pending_reply_overflow}}
  end

  # Helpers ------------------------------------------------------------------

  defp start_session(provider_options) do
    scope =
      start_supervised!(Supervisor.child_spec({CapabilityTree, owner: self()}, id: make_ref()))

    options = [provider: DuplexSTS, options: provider_options, owner: self()]
    {:ok, session, :starting} = Session.start(CapabilityTree.scope(scope), options)
    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}, 1_000
    assert :ok = Session.ack(session, ready)

    %{session: session, provider: Session.provider(session)}
  end

  defp push_chunks(session, text, encode_options \\ []) do
    context = make_ref()
    {:ok, pcm} = encode(text, encode_options)

    for <<chunk::binary-size(320) <- pcm>> do
      assert :ok = Session.push_audio(session, chunk, response_context: context)
    end

    remainder = rem(byte_size(pcm), 320)

    if remainder > 0 do
      <<_::binary-size(byte_size(pcm) - remainder), tail::binary>> = pcm
      assert :ok = Session.push_audio(session, tail, response_context: context)
    end
  end

  defp submit_text_turn(session, text, context) do
    case Session.push_text(session, text, response_context: context) do
      :ok ->
        drain_events(session)
        :ok

      {:error, _reason} = error ->
        error
    end
  end

  defp await_response_started(session, provider, remaining \\ 2_000)

  defp await_response_started(_session, _provider, 0), do: flunk("no response_started event")

  defp await_response_started(session, provider, remaining) do
    receive do
      {:vxpipe_speech, %Event{session: ^session, kind: :response_started, turn_ref: turn} = event} ->
        assert :ok = Session.ack(session, event)
        turn

      {:vxpipe_speech, %Event{session: ^session} = event} ->
        assert :ok = Session.ack(session, event)
        await_response_started(session, provider, remaining)
    after
      0 ->
        advance(provider, 20)
        await_response_started(session, provider, remaining - 1)
    end
  end

  # Admit every announced response, play its credited audio, settle each output,
  # and stop when the provider has no reply timeline left and no open slot.
  defp drive(session, provider, payloads \\ [], turns \\ [], outputs \\ %{}, remaining \\ 2_000)

  defp drive(_session, _provider, payloads, turns, _outputs, 0),
    do: {Enum.reverse(payloads), Enum.reverse(turns)}

  defp drive(session, provider, payloads, turns, outputs, remaining) do
    receive do
      {:vxpipe_speech, %Event{session: ^session, kind: :response_started, turn_ref: turn} = event} ->
        assert :ok = Session.ack(session, event)
        assert {:ok, output} = Session.admit_output(session, turn)

        drive(
          session,
          provider,
          payloads,
          [turn | turns],
          Map.put(outputs, turn, output),
          remaining
        )

      {:vxpipe_speech, %Event{session: ^session, kind: :output_completed, turn_ref: turn} = event} ->
        assert :ok = Session.ack(session, event)

        outputs =
          case Map.pop(outputs, turn) do
            {%{ref: reference} = output, rest} when reference == event.request_ref ->
              assert :ok = Session.settle_output(session, output, 0)
              rest

            _other ->
              outputs
          end

        drive(session, provider, payloads, turns, outputs, remaining)

      {:vxpipe_speech, %Event{session: ^session} = event} ->
        assert :ok = Session.ack(session, event)
        drive(session, provider, payloads, turns, outputs, remaining)

      {:vxpipe_speech_audio, %Audio{session: ^session} = audio} ->
        assert :ok = Session.validate_audio(session, audio)
        assert :ok = Session.ack_audio(session, audio)
        drive(session, provider, [audio.payload | payloads], turns, outputs, remaining)
    after
      0 ->
        state = :sys.get_state(provider)

        if Output.idle?(state.timeline) and state.segments == %{} do
          {Enum.reverse(payloads), Enum.reverse(turns)}
        else
          advance(provider, 20)
          drive(session, provider, payloads, turns, outputs, remaining - 1)
        end
    end
  end

  defp drain_until_tool_call(session) do
    receive do
      {:vxpipe_speech, %Event{session: ^session, kind: :tool_call, call_ref: ref} = event} ->
        assert :ok = Session.ack(session, event)
        ref

      {:vxpipe_speech, %Event{session: ^session} = event} ->
        assert :ok = Session.ack(session, event)
        drain_until_tool_call(session)
    after
      1_000 -> flunk("no tool_call event")
    end
  end

  defp drain_events(session) do
    receive do
      {:vxpipe_speech, %Event{session: ^session} = event} ->
        assert :ok = Session.ack(session, event)
        drain_events(session)
    after
      0 -> :ok
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

  defp advance(provider, ms), do: :ok = DuplexSTS.advance(provider, ms)

  defp encode(text, options) do
    {:ok, config} = Config.new(options)
    Encoder.encode(config, text)
  end
end
