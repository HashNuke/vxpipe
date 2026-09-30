defmodule Vxpipe.Gateway.Integration.DeepgramFluxOpusTest do
  use ExUnit.Case, async: false

  alias ExWebRTC.Media.Ogg.Reader
  alias Vxpipe.Providers.Deepgram.{Flux, STTSocket}
  alias Vxpipe.CallEngine.Provider.SpeechToText.Signal
  alias Vxpipe.Providers.Deepgram.LiveFixture

  @moduletag :live_providers
  @moduletag :live_deepgram
  @moduletag timeout: 60_000
  @audio_path LiveFixture.opus_path()

  setup_all do
    LiveFixture.ensure!()
    :ok
  end

  test "streams individual WebRTC-compatible Opus packets to Flux" do
    api_key = System.fetch_env!("DEEPGRAM_API_KEY")

    assert {:ok, provider} =
             Flux.new(
               api_key: api_key,
               model: Vxpipe.Providers.LiveModels.speech("deepgram", :stt_en),
               encoding: :opus,
               sample_rate: 48_000
             )

    socket =
      start_supervised!(%{
        id: {STTSocket, System.unique_integer([:positive])},
        start:
          {STTSocket, :start_link,
           [
             [
               owner: self(),
               connection: Flux.connection_options(provider),
               transport_options: [connect_timeout: 10_000, receive_timeout: 30_000]
             ]
           ]},
        restart: :temporary
      })

    assert %Signal{kind: :connected} = await_signal(socket, :connected, 10_000)

    assert {:ok, reader} = Reader.open(@audio_path)
    on_exit(fn -> Reader.close(reader) end)
    stream_packets(reader, socket)

    assert %Signal{kind: :turn_started, text: started_text} =
             await_signal(socket, :turn_started, 10_000)

    assert started_text != ""

    assert %Signal{kind: :turn_ended, text: final_text} =
             await_signal(socket, :turn_ended, 10_000)

    assert String.trim(final_text) != ""
  end

  defp stream_packets(reader, socket) do
    case Reader.next_packet(reader) do
      {:ok, {packet, duration_ms}, reader} ->
        assert :ok = STTSocket.send_audio(socket, packet)
        pace(duration_ms)
        stream_packets(reader, socket)

      :eof ->
        :ok

      {:error, reason} ->
        flunk("could not read the Opus fixture: #{inspect(reason)}")
    end
  end

  defp await_signal(socket, expected_kind, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await_signal(socket, expected_kind, deadline)
  end

  defp do_await_signal(socket, expected_kind, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:vxpipe_stt_transport, ^socket, {:message, payload}} ->
        case Flux.decode(payload) do
          {:ok, %Signal{kind: ^expected_kind} = signal} ->
            signal

          {:ok, %Signal{kind: :failed, provider_code: code}} ->
            flunk("Deepgram Flux failed with code #{code}")

          _other ->
            do_await_signal(socket, expected_kind, deadline)
        end

      {:vxpipe_stt_transport, ^socket, {:closed, _reason}} ->
        flunk("Deepgram Flux closed before #{expected_kind}")
    after
      remaining -> flunk("timed out waiting for Deepgram Flux #{expected_kind}")
    end
  end

  defp pace(0), do: :ok

  defp pace(duration_ms) do
    reference = make_ref()
    _timer = Process.send_after(self(), {:audio_pace, reference}, duration_ms)
    assert_receive {:audio_pace, ^reference}, duration_ms + 100
  end
end
