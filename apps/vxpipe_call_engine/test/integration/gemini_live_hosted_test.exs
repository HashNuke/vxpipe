defmodule Vxpipe.CallEngine.Integration.GeminiLiveHostedTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Media.PCMResampler
  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
  alias Vxpipe.Providers.Google.{STS, STSSession}
  alias Vxpipe.CallEngine.TestDeepgramAudioConfirmation
  alias Vxpipe.Providers.LiveModels

  @moduletag :live_providers
  @moduletag :live_gemini
  @moduletag timeout: 120_000
  @moduletag capture_log: true

  test "real microphone PCM produces credited speech and a subsequent typed turn" do
    deadline = System.monotonic_time(:millisecond) + 110_000
    scope = start_supervised!({CapabilityTree, owner: self()})

    assert {:ok, config} =
             STS.new(
               api_key: System.fetch_env!("GEMINI_API_KEY"),
               model: LiveModels.speech("google", :sts),
               voice: "Kore",
               system_prompt: "Speak briefly in English. Respond to greetings with Hello."
             )

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(scope),
               provider: STSSession,
               options: [model: config.model, voice: config.voice, response_start?: true],
               private: [config: config],
               owner: self()
             )

    state = %{outputs: %{}, bytes: 0, completed: 0, input: "", text: "", pcm: [], stream: nil}
    state = await(session, deadline, state, & &1.ready?)
    assert {:ok, descriptor} = Session.describe(session)
    assert descriptor.input_format.sample_rate == 16_000
    assert descriptor.format.sample_rate == 24_000
    assert descriptor.response_start?
    assert descriptor.barge_in == :room

    path = Path.expand("../fixtures/gpt_live/greeting_24k_mono_s16le.pcm", __DIR__)
    pcm = File.read!(path)
    assert byte_size(pcm) in 1..144_000
    {pcm, 0} = PCMResampler.resample(pcm, 0, 24_000, 16_000)
    # Pace real audio and its VAD tail while servicing output/event credit.
    pcm = pcm <> :binary.copy(<<0, 0>>, 32_000)
    reference = make_ref()
    send(self(), {:gemini_input_tick, reference})
    context = make_ref()
    state = %{state | stream: {reference, context, pcm}}
    first = await(session, deadline, state, &(&1.completed > 0 and &1.stream == nil))
    assert first.bytes > 0
    assert String.trim(first.input) != ""
    assert String.trim(heard_text(first, scope, deadline)) != ""
    assert first.outputs == %{}

    assert :ok =
             Session.push_text(session, "Say exactly the word violet.", response_context: context)

    second =
      await(session, deadline, %{first | text: "", pcm: []}, &(&1.completed > first.completed))

    assert second.bytes > first.bytes
    assert String.downcase(heard_text(second, scope, deadline)) =~ "violet"
    assert second.outputs == %{}
    assert :ok = Session.close(session)

    IO.puts(
      "Live Gemini: 16 kHz caller PCM, caller transcription, confirmed credited 24 kHz output and subsequent turn"
    )
  end

  for confirmation <- [:provider_or_deepgram, :deepgram] do
    @confirmation confirmation
    test "the configured fixed opening and subsequent turn receive independent output credit with #{confirmation} confirmation" do
      scope = start_supervised!({CapabilityTree, owner: self()})
      assert {:ok, config} = STS.new(api_key: System.fetch_env!("GEMINI_API_KEY"))

      assert {:ok, session, :starting} =
               Session.start(CapabilityTree.scope(scope),
                 provider: STSSession,
                 options: [response_start?: true],
                 private: [config: config],
                 owner: self()
               )

      deadline = System.monotonic_time(:millisecond) + 30_000
      state = %{outputs: %{}, bytes: 0, completed: 0, input: "", text: "", pcm: [], stream: nil}
      state = await(session, deadline, state, & &1.ready?)
      context = make_ref()
      assert :ok = Session.begin_opening(session, {:fixed, "Alpha."}, response_context: context)
      state = await(session, deadline, state, &(&1.completed > 0))
      assert state.bytes > 0
      if state.text != "", do: assert(state.text == "Alpha.")
      # Exercise independent recognition even when this run has a provider transcript.
      confirmed = if @confirmation == :deepgram, do: %{state | text: ""}, else: state
      assert words(heard_text(confirmed, scope, deadline)) == ["alpha"]

      if state.text == "",
        do: IO.puts("Live Gemini fixed opening: missing provider transcript confirmed from PCM")

      assert state.outputs == %{}

      assert :ok =
               Session.push_text(session, "Say exactly the word violet.",
                 response_context: context
               )

      second =
        await(session, deadline, %{state | text: "", pcm: []}, &(&1.completed > state.completed))

      assert second.bytes > state.bytes
      assert second.outputs == %{}
      assert String.downcase(heard_text(second, scope, deadline)) =~ "violet"
      assert :ok = Session.close(session)
    end
  end

  defp heard_text(%{text: text}, _scope, _deadline) when text != "", do: text

  # Test-only confirmation of real PCM; production has no recognition fallback.
  defp heard_text(state, _scope, deadline) do
    pcm = IO.iodata_to_binary(Enum.reverse(state.pcm))
    assert byte_size(pcm) in 2..2_097_152

    assert {:ok, text} =
             TestDeepgramAudioConfirmation.transcribe(
               pcm,
               24_000,
               System.fetch_env!("DEEPGRAM_API_KEY"),
               timeout_ms: remaining(deadline)
             )

    IO.puts("Live Gemini output confirmed with test-only Deepgram recognition")
    text
  end

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)

  defp words(text) do
    text |> String.downcase() |> String.replace(~r/[^\p{L}\p{N}]+/u, " ") |> String.split()
  end

  defp await(session, deadline, state, done?) do
    if done?.(Map.put_new(state, :ready?, false)) do
      state
    else
      receive do
        {:vxpipe_speech, %Event{session: ^session} = event} ->
          assert :ok = Session.ack(session, event)
          state = track(session, event, state)
          await(session, deadline, state, done?)

        {:vxpipe_speech_audio, %Audio{session: ^session} = audio} ->
          assert :ok = Session.validate_audio(session, audio)
          assert byte_size(audio.payload) > 0 and rem(byte_size(audio.payload), 2) == 0
          assert :ok = Session.ack_audio(session, audio)

          await(
            session,
            deadline,
            %{
              state
              | bytes: state.bytes + byte_size(audio.payload),
                pcm: [audio.payload | state.pcm]
            },
            done?
          )

        {:gemini_input_tick, reference} ->
          state = push_frame(session, state, reference)
          await(session, deadline, state, done?)

        {:vxpipe_speech_closed, ^session, reason} ->
          flunk("Gemini hosted session closed: #{inspect(reason)}")
      after
        max(deadline - System.monotonic_time(:millisecond), 0) ->
          flunk(
            "Gemini hosted acceptance deadline expired: #{inspect(Map.take(state, [:bytes, :completed, :ready?]))}"
          )
      end
    end
  end

  defp push_frame(session, %{stream: {reference, context, pcm}} = state, reference) do
    size = min(byte_size(pcm), 640)
    <<frame::binary-size(size), rest::binary>> = pcm
    assert :ok = Session.push_audio(session, frame, response_context: context)

    if rest == <<>> do
      %{state | stream: nil}
    else
      Process.send_after(self(), {:gemini_input_tick, reference}, 20)
      %{state | stream: {reference, context, rest}}
    end
  end

  defp push_frame(_session, state, _reference), do: state

  defp track(_session, %Event{kind: :ready}, state), do: Map.put(state, :ready?, true)

  defp track(session, %Event{kind: kind, turn_ref: turn}, state)
       when kind in [:response_started, :opening_started] do
    assert {:ok, handle} = Session.admit_output(session, turn)
    %{state | outputs: Map.put(state.outputs, turn, handle)}
  end

  defp track(session, %Event{kind: :output_completed, turn_ref: turn}, state) do
    {handle, outputs} = Map.pop(state.outputs, turn)
    assert handle != nil
    # Direct consumer acknowledges receipt only; this is not remote phone playout.
    assert :ok = Session.settle_output(session, handle, 0)
    %{state | outputs: outputs, completed: state.completed + 1}
  end

  defp track(_session, %Event{kind: :input_transcript, text: text}, state),
    do: %{state | input: state.input <> text}

  defp track(_session, %Event{kind: :output_transcript, text: text}, state),
    do: %{state | text: state.text <> text}

  defp track(_session, %Event{kind: :failed}, _state), do: flunk("Gemini hosted provider failed")
  defp track(_session, _event, state), do: state
end
