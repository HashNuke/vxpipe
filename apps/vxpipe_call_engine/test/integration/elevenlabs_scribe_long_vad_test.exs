defmodule Vxpipe.CallEngine.Integration.ElevenLabsScribeLongVADTest do
  use ExUnit.Case, async: false
  @moduletag :live_providers
  @moduletag :live_elevenlabs
  @moduletag :capture_log
  @moduletag timeout: 100_000

  alias Vxpipe.Providers.Deepgram.LiveFixture
  alias Vxpipe.Providers.ElevenLabs.{Scribe, ScribeSocket}
  alias Vxpipe.Providers.LiveModels

  test "one bounded long VAD stream preserves transcription and records segment timing" do
    fixture = File.read!(LiveFixture.pcm_path())
    speech_bytes = byte_size(fixture) - 64_000
    assert speech_bytes > 0 and rem(speech_bytes, 2) == 0
    <<phrase::binary-size(speech_bytes), trailing::binary>> = fixture
    assert trailing == :binary.copy(<<0>>, 64_000)

    # Remove only the fixture generator's known two-second silence tail.
    # Repetition is a protocol experiment, not a natural acoustic quality corpus.
    speech = :binary.copy(phrase, 19)
    assert byte_size(speech) > 36 * 32_000
    assert byte_size(speech) + 64_000 <= 45 * 32_000

    assert {:ok, config} =
             Scribe.new(
               api_key: System.fetch_env!("ELEVENLABS_API_KEY"),
               model: LiveModels.speech("elevenlabs", :stt),
               language_code: "en",
               commit_strategy: :vad
             )

    socket =
      start_supervised!(%{
        id: make_ref(),
        start:
          {ScribeSocket, :start_link,
           [
             [
               owner: self(),
               connection: Scribe.connection_options(config),
               commit_strategy: config.commit_strategy,
               transport_options: []
             ]
           ]},
        restart: :temporary
      })

    assert_receive {:vxpipe_socket_connected, ^socket}, 15_000
    assert_receive {:vxpipe_scribe_transport, ^socket, {:event, {:ready, _id}}}, 5_000

    observations = stream(socket, speech, :speech, 0, [])

    observations =
      stream(socket, :binary.copy(<<0>>, 64_000), :silence, byte_size(speech), observations)

    observations =
      await_tail(
        socket,
        observations,
        byte_size(speech) + 64_000,
        System.monotonic_time(:millisecond) + 15_000
      )

    # Only counts, receipt positions and a public-fixture match leave this test.
    # Receipt position is not provider-processed-through or a commit reason.
    summary =
      observations
      |> Enum.reverse()
      |> Enum.map(fn {phase, bytes, text} ->
        %{
          phase: phase,
          accepted_audio_ms: div(bytes, 32),
          transcript_bytes: byte_size(text),
          known_word?: String.downcase(text) =~ "telescope"
        }
      end)

    assert Enum.any?(summary, & &1.known_word?)
    IO.puts("Scribe bounded long VAD observations: " <> inspect(summary))
  end

  defp stream(_socket, "", _phase, _accepted, observations), do: observations

  defp stream(socket, pcm, phase, accepted, observations) do
    size = min(byte_size(pcm), 3_200)
    <<chunk::binary-size(size), remaining::binary>> = pcm
    assert :ok = ScribeSocket.send_audio(socket, chunk)
    accepted = accepted + size
    reference = make_ref()
    Process.send_after(self(), {:audio_pace, reference}, div(size, 32))

    observations =
      await_pace(
        socket,
        reference,
        phase,
        accepted,
        observations,
        System.monotonic_time(:millisecond) + 1_000
      )

    stream(socket, remaining, phase, accepted, observations)
  end

  defp await_pace(socket, reference, phase, accepted, observations, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)
    assert remaining > 0, "Long VAD pacing deadline exceeded"

    receive do
      {:audio_pace, ^reference} ->
        observations

      {:vxpipe_scribe_transport, ^socket, {:event, {:partial, _text}}} ->
        await_pace(socket, reference, phase, accepted, observations, deadline)

      {:vxpipe_scribe_transport, ^socket, {:event, {:segment, text}}} ->
        await_pace(
          socket,
          reference,
          phase,
          accepted,
          [{phase, accepted, text} | observations],
          deadline
        )

      {:vxpipe_scribe_transport, ^socket, _closed} ->
        flunk("Scribe closed during the bounded long VAD stream")
    after
      remaining -> flunk("Long VAD pacing acknowledgement was missing")
    end
  end

  defp await_tail(socket, observations, accepted, deadline) do
    if Enum.any?(observations, fn {phase, _bytes, _text} -> phase in [:silence, :drain] end) do
      observations
    else
      remaining = deadline - System.monotonic_time(:millisecond)
      assert remaining > 0, "Scribe exceeded its long VAD transcript deadline"

      receive do
        {:vxpipe_scribe_transport, ^socket, {:event, {:partial, _text}}} ->
          await_tail(socket, observations, accepted, deadline)

        {:vxpipe_scribe_transport, ^socket, {:event, {:segment, text}}} ->
          [{:drain, accepted, text} | observations]

        {:vxpipe_scribe_transport, ^socket, _closed} ->
          flunk("Scribe closed before the long VAD tail transcript")
      after
        remaining -> flunk("Scribe did not return its long VAD tail transcript")
      end
    end
  end
end
