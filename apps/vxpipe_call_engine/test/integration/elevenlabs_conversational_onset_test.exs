defmodule Vxpipe.CallEngine.Integration.ElevenLabsConversationalOnsetTest do
  use ExUnit.Case, async: false
  @moduletag :live_providers
  @moduletag :live_elevenlabs
  @moduletag :capture_log
  @moduletag timeout: 120_000

  alias Vxpipe.CallEngine.Speech.{CapabilityTree, ConversationalSTT, Event, Session}
  alias Vxpipe.CallEngine.SpeechToTextRuntime
  alias Vxpipe.Providers.Deepgram.LiveFixture
  alias Vxpipe.Providers.ElevenLabs.{Scribe, STTSession}
  alias Vxpipe.Providers.LiveModels

  for vad <- [false, true] do
    @vad vad
    test "continuous Scribe preserves distinct turns with local VAD=#{vad}" do
      session = start_session(@vad)

      first =
        stream(session, File.read!(LiveFixture.pcm_path()) <> :binary.copy(<<0>>, 64_000), [])

      first = drain(session, first)
      assert_turns(first, ["telescope"])
      assert stream(session, :binary.copy(<<0>>, 96_000), []) == []

      second =
        stream(
          session,
          File.read!(LiveFixture.short_pcm_path()) <> :binary.copy(<<0>>, 64_000),
          []
        )

      second = drain(session, second)
      assert_turns(second, ["yes"])
      assert List.first(first).turn_ref != List.first(second).turn_ref
      assert stream(session, :binary.copy(<<0>>, 96_000), []) == []

      repeated =
        stream(
          session,
          File.read!(LiveFixture.short_pcm_path()) <> :binary.copy(<<0>>, 64_000),
          []
        )
        |> then(&drain(session, &1))

      assert_turns(repeated, ["yes"])
      assert List.first(second).turn_ref != List.first(repeated).turn_ref
      assert stream(session, :binary.copy(<<0>>, 96_000), []) == []
      assert :ok = Session.close(session)
      IO.puts("Scribe conversational distinct/repeated-turn acceptance: vad=#{@vad}, turns=3")
    end

    test "continuous Scribe ignores background noise and retains speech with local VAD=#{vad}" do
      session = start_session(@vad)
      assert stream(session, background_noise(:binary.copy(<<0>>, 96_000)), []) == []

      audio =
        (File.read!(LiveFixture.pcm_path()) <> :binary.copy(<<0>>, 64_000))
        |> background_noise()

      events = stream(session, audio, []) |> then(&drain(session, &1))
      assert_turns(events, ["telescope"])
      assert stream(session, background_noise(:binary.copy(<<0>>, 96_000)), []) == []
      assert :ok = Session.close(session)
      IO.puts("Scribe conversational background-noise acceptance: vad=#{@vad}")
    end

    test "continuous Scribe retains one long utterance across forced segments with local VAD=#{vad}" do
      session = start_session(@vad)
      fixture = File.read!(LiveFixture.pcm_path())
      bytes = byte_size(fixture) - 64_000
      <<phrase::binary-size(bytes), tail::binary>> = fixture
      assert tail == :binary.copy(<<0>>, 64_000)
      audio = :binary.copy(phrase, 19) <> :binary.copy(<<0>>, 128_000)
      events = stream(session, audio, []) |> then(&drain(session, &1))
      assert_turns(events, ["telescope"])
      assert :ok = Session.close(session)

      IO.puts(
        "Scribe conversational long-input acceptance: vad=#{@vad}, audio_ms=#{div(byte_size(audio), 32)}"
      )
    end
  end

  # Reproducible low-level broadband noise, mixed into public synthetic speech.
  # It exercises a bounded background-noise case, not arbitrary microphone noise.
  defp background_noise(pcm) do
    seed = :rand.seed_s(:exsss, {17, 29, 43})

    {samples, _seed} =
      Enum.map_reduce(for(<<sample::little-signed-16 <- pcm>>, do: sample), seed, fn sample,
                                                                                     seed ->
        {noise, next_seed} = :rand.uniform_s(401, seed)
        mixed = max(-32_768, min(32_767, sample + noise - 201))
        {<<mixed::little-signed-16>>, next_seed}
      end)

    IO.iodata_to_binary(samples)
  end

  defp start_session(vad) do
    assert {:ok, config} =
             Scribe.new(
               api_key: System.fetch_env!("ELEVENLABS_API_KEY"),
               model: LiveModels.speech("elevenlabs", :stt),
               language_code: "en",
               commit_strategy: :vad
             )

    assert {:ok, {provider, options}, private} =
             SpeechToTextRuntime.provider({STTSession, config}, [])

    private =
      if System.get_env("VXPIPE_TRACE_SCRIBE") == "1",
        do:
          Keyword.merge(private,
            wire_module: Vxpipe.CallEngine.ScribeEvidenceSocket,
            wire_options: [observer: self()]
          ),
        else: private

    tree = start_supervised!({CapabilityTree, owner: self()}, id: make_ref())

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: ConversationalSTT,
               options: [provider: provider, options: options, vad: vad],
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
    events = await_pace(session, token, events)
    stream(session, remaining, events)
  end

  defp await_pace(session, token, events) do
    receive do
      {:scribe_wire_evidence, summary} ->
        IO.puts("Scribe wire evidence: " <> inspect(summary))
        await_pace(session, token, events)

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

  defp drain(session, events) do
    drain_until(session, events, System.monotonic_time(:millisecond) + 10_000)
  end

  defp drain_until(session, events, deadline) do
    if Enum.any?(events, &(&1.kind == :turn_ended)) do
      events
    else
      assert System.monotonic_time(:millisecond) < deadline, "recognition did not settle"
      # Conversational input stays live during silence; stopping bytes would
      # turn this into a finite-input test, which Scribe does not advertise.
      next = stream(session, :binary.copy(<<0>>, 640), [])
      drain_until(session, events ++ next, deadline)
    end
  end

  defp assert_turns(events, expected_words) do
    starts = Enum.filter(events, &(&1.kind == :speech_started))
    ends = Enum.filter(events, &(&1.kind == :turn_ended))
    assert length(starts) == length(expected_words)
    assert length(ends) == length(expected_words)
    assert List.first(events).kind == :speech_started
    assert List.last(events).kind == :turn_ended
    assert Enum.map(starts, & &1.turn_ref) == Enum.map(ends, & &1.turn_ref)

    for {ended, word} <- Enum.zip(ends, expected_words) do
      assert String.downcase(ended.text) =~ word
      assert ended.endpointing == :inferred_gap
      assert Enum.any?(events, &(&1.kind == :transcript and &1.turn_ref == ended.turn_ref))
    end
  end
end
