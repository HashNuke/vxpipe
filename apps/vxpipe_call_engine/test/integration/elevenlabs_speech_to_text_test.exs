defmodule Vxpipe.CallEngine.Integration.ElevenLabsSpeechToTextTest do
  use ExUnit.Case, async: false
  @moduletag :live_providers
  @moduletag :live_elevenlabs
  @moduletag :capture_log
  @moduletag timeout: 90_000
  alias Vxpipe.CallEngine.Speech.{CapabilityTree, Event, Session}
  alias Vxpipe.Providers.Deepgram.LiveFixture
  alias Vxpipe.Providers.ElevenLabs.{Scribe, STTSession}
  alias Vxpipe.CallEngine.LiveScribeSocket
  alias Vxpipe.Providers.LiveModels

  test "recognizes the first answer after thirty seconds without caller audio" do
    assert :ok = LiveFixture.ensure_short!()
    tree = start_supervised!({CapabilityTree, owner: self()})

    assert {:ok, config} =
             Scribe.new(
               api_key: System.fetch_env!("ELEVENLABS_API_KEY"),
               model: LiveModels.speech("elevenlabs", :stt),
               language_code: "en"
             )

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: STTSession,
               options: [language_code: "en"],
               private: [config: config]
             )

    assert_receive {:vxpipe_speech, %Event{kind: :ready} = ready}, 20_000
    assert :ok = Session.ack(session, ready)
    ref = make_ref()
    Process.send_after(self(), {:idle_elapsed, ref}, 30_000)

    receive do
      {:idle_elapsed, ^ref} ->
        :ok

      {:vxpipe_speech, %Event{kind: kind}} ->
        flunk("prepared Scribe allocation emitted #{kind} during initial idle")
    after
      31_000 -> flunk("idle acceptance deadline did not arrive")
    end

    pcm = File.read!(LiveFixture.short_pcm_path())
    events = stream(session, pcm <> :binary.copy(<<0>>, 32_768), [])
    events = await_ends(session, events, System.monotonic_time(:millisecond) + 15_000, 1)

    assert [%Event{kind: :speech_started, turn_ref: turn}] =
             Enum.filter(events, &(&1.kind == :speech_started))

    assert [%Event{kind: :turn_ended, turn_ref: ^turn} = ended] =
             Enum.filter(events, &(&1.kind == :turn_ended))

    assert ended.endpointing == :local_gap

    assert Regex.match?(~r/\byes\b/i, ended.text),
           "answer after idle was not recognized (#{byte_size(ended.text)} text bytes)"

    IO.puts("Scribe initial idle: 30 seconds without caller audio; first answer settled")
    assert :ok = Session.close(session)
  end

  @tag :live_scribe_silence
  test "recognizes speech after forty seconds of actual silent PCM" do
    assert :ok = LiveFixture.ensure_short!()
    tree = start_supervised!({CapabilityTree, owner: self()})

    assert {:ok, config} =
             Scribe.new(
               api_key: System.fetch_env!("ELEVENLABS_API_KEY"),
               model: LiveModels.speech("elevenlabs", :stt),
               language_code: "en"
             )

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: STTSession,
               options: [language_code: "en"],
               private: [
                 config: config,
                 wire_module: LiveScribeSocket,
                 wire_options: [observer: self()]
               ]
             )

    assert_receive {:vxpipe_speech, %Event{kind: :ready} = ready}, 20_000
    assert :ok = Session.ack(session, ready)
    assert_receive {:live_scribe_socket, wire}, 1_000
    monitor = Process.monitor(wire)
    assert [] == stream(session, :binary.copy(<<0>>, 40 * 32_000), [])

    pcm = File.read!(LiveFixture.short_pcm_path())
    events = stream(session, pcm <> :binary.copy(<<0>>, 32_768), [])
    events = await_ends(session, events, System.monotonic_time(:millisecond) + 15_000, 1)

    assert [%Event{kind: :speech_started, turn_ref: turn}] =
             Enum.filter(events, &(&1.kind == :speech_started))

    assert [%Event{kind: :turn_ended, turn_ref: ^turn} = ended] =
             Enum.filter(events, &(&1.kind == :turn_ended))

    assert ended.endpointing == :local_gap

    assert Regex.match?(~r/\byes\b/i, ended.text),
           "answer after idle was not recognized (#{byte_size(ended.text)} text bytes)"

    refute_received {:live_scribe_socket, _replacement}
    refute_received {:DOWN, ^monitor, :process, ^wire, _reason}
    assert :ok = Session.close(session)
    assert_receive {:DOWN, ^monitor, :process, ^wire, _reason}, 5_000
  end

  test "recognizes a brief first answer below the initial processing window" do
    assert :ok = LiveFixture.ensure_short!()
    tree = start_supervised!({CapabilityTree, owner: self()})

    assert {:ok, config} =
             Scribe.new(
               api_key: System.fetch_env!("ELEVENLABS_API_KEY"),
               model: LiveModels.speech("elevenlabs", :stt),
               language_code: "en"
             )

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: STTSession,
               options: [language_code: "en"],
               private: [config: config]
             )

    assert_receive {:vxpipe_speech, %Event{kind: :ready} = ready}, 20_000
    assert :ok = Session.ack(session, ready)
    pcm = File.read!(LiveFixture.short_pcm_path())
    assert byte_size(pcm) <= 64_000
    events = stream(session, pcm <> :binary.copy(<<0>>, 32_768), [])

    events =
      await_ends(session, events, System.monotonic_time(:millisecond) + 15_000, 1)

    assert [%Event{kind: :speech_started, turn_ref: turn}] =
             Enum.filter(events, &(&1.kind == :speech_started))

    assert [%Event{kind: :turn_ended, turn_ref: ^turn} = ended] =
             Enum.filter(events, &(&1.kind == :turn_ended))

    assert ended.endpointing == :local_gap
    assert ended.audio_duration_ms in 1..1_200

    assert Regex.match?(~r/\byes\b/i, ended.text),
           "brief answer was not recognized (#{byte_size(ended.text)} text bytes)"

    IO.puts("Scribe short answer: local onset/end, known word and sub-two-second acoustic input")
    assert :ok = Session.close(session)
  end

  @tag :live_scribe_distinct
  test "one socket recognizes two distinct acoustically detected turns" do
    check_two_turns(
      File.read!(LiveFixture.short_pcm_path()) <> :binary.copy(<<0>>, 32_768),
      "yes"
    )
  end

  @tag :live_scribe_repeat
  test "one socket recognizes the same recording in consecutive acoustic turns" do
    check_two_turns(File.read!(LiveFixture.pcm_path()), "telescope")
  end

  defp check_two_turns(second_pcm, expected_second_word) do
    tree = start_supervised!({CapabilityTree, owner: self()})

    assert {:ok, config} =
             Scribe.new(
               api_key: System.fetch_env!("ELEVENLABS_API_KEY"),
               model: LiveModels.speech("elevenlabs", :stt),
               language_code: "en"
             )

    assert {:ok, session, :starting} =
             Session.start(CapabilityTree.scope(tree),
               provider: STTSession,
               options: [language_code: "en"],
               private: [
                 config: config,
                 wire_module: LiveScribeSocket,
                 wire_options: [observer: self()]
               ]
             )

    assert_receive {:vxpipe_speech, %Event{kind: :ready} = ready}, 20_000
    assert :ok = Session.ack(session, ready)
    assert_receive {:live_scribe_socket, wire}, 1_000
    monitor = Process.monitor(wire)
    pcm = File.read!(LiveFixture.pcm_path())
    assert byte_size(pcm) <= 5 * 32_000

    events = stream(session, pcm, [])
    events = stream(session, second_pcm, events)
    events = await_ends(session, events, System.monotonic_time(:millisecond) + 15_000)
    starts = Enum.filter(events, &(&1.kind == :speech_started))
    ends = Enum.filter(events, &(&1.kind == :turn_ended))
    assert length(starts) == 2 and length(ends) == 2
    refs = Enum.map(starts, & &1.turn_ref)
    assert length(Enum.uniq(refs)) == 2
    assert Enum.map(ends, & &1.turn_ref) == refs
    assert Enum.all?(ends, &(&1.endpointing == :local_gap and &1.audio_duration_ms > 0))
    expected_words = ["telescope", expected_second_word]

    known_words? =
      Enum.zip(ends, expected_words)
      |> Enum.all?(fn {event, word} -> String.downcase(event.text) =~ word end)

    evidence =
      Enum.zip_with(ends, expected_words, fn event, word ->
        %{
          duration_ms: event.audio_duration_ms,
          text_bytes: byte_size(event.text),
          known_word?: String.downcase(event.text) =~ word
        }
      end)

    assert known_words?, "Scribe public-fixture evidence: #{inspect(evidence)}"
    IO.puts("Scribe owned STT: 2 acoustic starts; 2 settled local-gap ends; fixture word present")
    refute_received {:live_scribe_socket, _replacement}
    refute_received {:DOWN, ^monitor, :process, ^wire, _reason}
    assert :ok = Session.close(session)
  end

  defp stream(_session, "", events), do: events

  defp stream(session, audio, events) do
    size = min(byte_size(audio), 3_200)
    <<chunk::binary-size(size), rest::binary>> = audio
    assert :ok = Session.push_audio(session, chunk)
    ref = make_ref()
    Process.send_after(self(), {:audio_pace, ref}, div(size, 32))
    events = await_pace(session, ref, events, System.monotonic_time(:millisecond) + 1_000)
    stream(session, rest, events)
  end

  defp await_pace(session, ref, events, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)
    assert remaining > 0, "bounded PCM pacing exceeded its deadline"

    receive do
      {:audio_pace, ^ref} ->
        events

      {:vxpipe_speech, event} ->
        assert :ok = Session.ack(session, event)
        await_pace(session, ref, events ++ [event], deadline)

      {:vxpipe_speech_closed, ^session, _reason} ->
        flunk("Scribe allocation closed during input")
    after
      remaining -> flunk("PCM pacing acknowledgement missing")
    end
  end

  defp await_ends(session, events, deadline, expected \\ 2) do
    if Enum.count(events, &(&1.kind == :turn_ended)) == expected do
      events
    else
      remaining = deadline - System.monotonic_time(:millisecond)
      assert remaining > 0, "Scribe did not settle both caller turns"

      receive do
        {:vxpipe_speech, event} ->
          assert :ok = Session.ack(session, event)
          await_ends(session, events ++ [event], deadline, expected)

        {:vxpipe_speech_closed, ^session, _reason} ->
          flunk("Scribe closed before turn settlement")
      after
        remaining -> flunk("Scribe final recognition did not arrive")
      end
    end
  end
end
