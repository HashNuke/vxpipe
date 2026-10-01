defmodule Vxpipe.CallEngine.Integration.ElevenLabsScribeProtocolTest do
  use ExUnit.Case, async: false
  @moduletag :live_providers
  @moduletag :live_elevenlabs
  @moduletag :capture_log
  @moduletag timeout: 45_000

  alias Vxpipe.Providers.Deepgram.LiveFixture
  alias Vxpipe.Providers.ElevenLabs.{Scribe, ScribeSocket}
  alias Vxpipe.Providers.LiveModels

  test "one bounded stream acknowledges configuration and commits the existing sample" do
    # This protocol check does not claim speech-start, turn-end or room admission.
    pcm = File.read!(LiveFixture.pcm_path()) <> :binary.copy(<<0, 0>>, 16_000)
    assert rem(byte_size(pcm), 2) == 0
    assert byte_size(pcm) <= 16_000 * 2 * 10

    assert {:ok, config} =
             Scribe.new(
               api_key: System.fetch_env!("ELEVENLABS_API_KEY"),
               model: LiveModels.speech("elevenlabs", :stt),
               language_code: "en"
             )

    socket =
      start_supervised!(%{
        id: make_ref(),
        start:
          {ScribeSocket, :start_link,
           [[owner: self(), connection: Scribe.connection_options(config), transport_options: []]]},
        restart: :temporary
      })

    assert_receive {:vxpipe_socket_connected, ^socket}, 15_000
    assert_receive {:vxpipe_scribe_transport, ^socket, {:event, {:ready, _session_id}}}, 5_000

    stream_audio(socket, pcm)
    assert :ok = ScribeSocket.commit(socket)
    segment = await_segment(socket, System.monotonic_time(:millisecond) + 15_000)

    assert String.downcase(segment) =~ "telescope",
           "Scribe did not preserve the fixture's known final word"
  end

  test "VAD mode commits the bounded existing sample without a manual commit" do
    # This proves automatic segment finalization only, not speech-start or room admission.
    pcm = File.read!(LiveFixture.pcm_path()) <> :binary.copy(<<0, 0>>, 16_000 * 2)
    assert rem(byte_size(pcm), 2) == 0
    assert byte_size(pcm) <= 16_000 * 2 * 10

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
    assert_receive {:vxpipe_scribe_transport, ^socket, {:event, {:ready, _session_id}}}, 5_000
    stream_audio(socket, pcm)
    segment = await_segment(socket, System.monotonic_time(:millisecond) + 15_000)

    assert String.downcase(segment) =~ "telescope",
           "Scribe VAD did not preserve the fixture's known final word"
  end

  defp stream_audio(_socket, ""), do: :ok

  defp stream_audio(socket, pcm) do
    size = min(byte_size(pcm), 3_200)
    <<chunk::binary-size(size), remaining::binary>> = pcm
    assert :ok = ScribeSocket.send_audio(socket, chunk)
    reference = make_ref()
    Process.send_after(self(), {:audio_pace, reference}, div(size, 32))
    assert_receive {:audio_pace, ^reference}, 1_000
    stream_audio(socket, remaining)
  end

  defp await_segment(socket, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)
    assert remaining > 0, "Scribe exceeded its transcript deadline"

    receive do
      {:vxpipe_scribe_transport, ^socket, {:event, {:partial, _text}}} ->
        await_segment(socket, deadline)

      {:vxpipe_scribe_transport, ^socket, {:event, {:segment, text}}} ->
        text

      {:vxpipe_scribe_transport, ^socket, _closed} ->
        flunk("Scribe closed before its committed transcript")
    after
      remaining -> flunk("Scribe did not return its committed transcript")
    end
  end
end
