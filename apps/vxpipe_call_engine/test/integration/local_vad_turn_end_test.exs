defmodule Vxpipe.CallEngine.Integration.LocalVADTurnEndTest do
  @moduledoc """
  Live local-VAD turn end across recognizers other than Scribe (Scribe is covered
  by `ElevenLabsConversationalOnsetTest`). Real Silero decides start and end; Flux
  and Gemini are finalized on request, Cartesia relies on the bounded final wait.
  Each case reports the delay from the end of speech audio to the turn end.
  """
  use ExUnit.Case, async: false
  @moduletag :live_providers
  @moduletag :capture_log
  @moduletag timeout: 120_000

  alias Vxpipe.CallEngine.Speech.{CapabilityTree, ConversationalSTT, Event, Session}
  alias Vxpipe.CallEngine.SpeechToTextRuntime
  alias Vxpipe.Providers.Cartesia.STT, as: CartesiaSTT
  alias Vxpipe.Providers.Cartesia.STTSession, as: CartesiaSTTSession
  alias Vxpipe.Providers.Deepgram.{Flux, LiveFixture}
  alias Vxpipe.Providers.Deepgram.STTSession, as: FluxSession
  alias Vxpipe.Providers.Google.STT, as: GoogleSTT
  alias Vxpipe.Providers.Google.STTSession, as: GoogleSTTSession

  @tag :live_deepgram
  test "Deepgram Flux ends one turn per answer on local silence" do
    assert {:ok, config} =
             Flux.new(
               api_key: System.fetch_env!("DEEPGRAM_API_KEY"),
               model: "flux-general-en",
               encoding: :linear16,
               sample_rate: 16_000
             )

    assert_answers({FluxSession, config}, "deepgram flux")
  end

  @tag :live_gemini
  test "Gemini Transcribe Live ends one turn per answer on local silence" do
    assert {:ok, config} = GoogleSTT.new(api_key: System.fetch_env!("GEMINI_API_KEY"))
    assert_answers({GoogleSTTSession, config}, "gemini transcribe")
  end

  @tag :live_cartesia
  test "Cartesia Ink 2 ends one turn per answer on local silence" do
    assert {:ok, config} = CartesiaSTT.new(api_key: System.fetch_env!("CARTESIA_API_KEY"))
    assert_answers({CartesiaSTTSession, config}, "cartesia ink-2")
  end

  defp assert_answers(selected, label) do
    session = start_session(selected)

    for {fixture, word} <- [
          {LiveFixture.pcm_path(), "telescope"},
          {LiveFixture.short_pcm_path(), "yes"}
        ] do
      speech = File.read!(fixture)
      events = stream(session, speech, [])
      speech_end = System.monotonic_time(:millisecond)
      {events, ended_at} = drain(session, events, speech_end + 10_000)

      starts = Enum.filter(events, &(&1.kind == :speech_started))
      ends = Enum.filter(events, &(&1.kind == :turn_ended))
      assert [%Event{turn_ref: turn}] = starts
      assert [%Event{turn_ref: ^turn} = ended] = ends
      assert ended.endpointing == :local_gap
      assert String.downcase(ended.text) =~ word

      IO.puts(
        "Local VAD turn end (#{label}): word=#{word}, " <>
          "speech_end_to_turn_end_ms=#{ended_at - speech_end}"
      )

      # The next answer begins after a quiet gap with no phantom turn.
      assert stream(session, :binary.copy(<<0>>, 32_000), []) == []
    end

    assert :ok = Session.close(session)
  end

  defp start_session(selected) do
    assert {:ok, {provider, options}, private} = SpeechToTextRuntime.provider(selected, [])
    tree = start_supervised!({CapabilityTree, owner: self()}, id: make_ref())

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: ConversationalSTT,
               options: [provider: provider, options: options, vad: true],
               private: [
                 recognizer: provider,
                 recognizer_options: options,
                 recognizer_private: private
               ],
               start_timeout: 30_000
             )

    assert_receive {:vxpipe_speech, %Event{session: ^session, kind: :ready} = ready}, 30_000
    assert :ok = Session.ack(session, ready)
    session
  end

  defp stream(_session, "", events), do: Enum.reverse(events)

  defp stream(session, audio, events) do
    bytes = min(byte_size(audio), 640)
    <<chunk::binary-size(bytes), remaining::binary>> = audio
    assert :ok = Session.push_audio(session, chunk)
    token = make_ref()
    Process.send_after(self(), {:pace, token}, div(bytes, 32))
    stream(session, remaining, await_pace(session, token, events))
  end

  defp await_pace(session, token, events) do
    receive do
      {:pace, ^token} ->
        events

      {:vxpipe_speech, %Event{session: ^session} = event} ->
        assert :ok = Session.ack(session, event)
        assert event.kind != :failed
        await_pace(session, token, [event | events])

      {:vxpipe_speech_closed, ^session, reason} ->
        flunk("speech allocation closed: #{reason}")
    after
      1_000 -> flunk("audio pacing deadline exceeded")
    end
  end

  # Live input continues as paced silence until the turn ends; returns the
  # events and the time the turn end was observed.
  defp drain(session, events, deadline) do
    if Enum.any?(events, &(&1.kind == :turn_ended)) do
      {events, System.monotonic_time(:millisecond)}
    else
      assert System.monotonic_time(:millisecond) < deadline, "turn did not end"
      next = stream(session, :binary.copy(<<0>>, 640), [])
      drain(session, events ++ next, deadline)
    end
  end
end
