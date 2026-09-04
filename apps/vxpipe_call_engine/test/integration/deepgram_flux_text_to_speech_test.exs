defmodule Vxpipe.CallEngine.Integration.DeepgramFluxTextToSpeechTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Provider.Deepgram.{
    FluxTextToSpeech,
    FluxTextToSpeechSocket
  }

  alias Vxpipe.CallEngine.Provider.TextToSpeech.Signal

  @moduletag :integration
  @moduletag timeout: 60_000

  test "streams nonempty 48 kHz linear16 audio and a terminal boundary" do
    provider =
      FluxTextToSpeech.new!(
        api_key: System.fetch_env!("DEEPGRAM_API_KEY"),
        model: "flux-haley-en",
        encoding: :linear16,
        sample_rate: 48_000
      )

    socket =
      start_supervised!(%{
        id: {FluxTextToSpeechSocket, System.unique_integer([:positive])},
        start:
          {FluxTextToSpeechSocket, :start_link,
           [
             [
               owner: self(),
               connection: FluxTextToSpeech.connection_options(provider),
               transport_options: [connect_timeout: 10_000, receive_timeout: 30_000]
             ]
           ]},
        restart: :temporary
      })

    assert %Signal{kind: :connected} = await_control(socket, :connected, 10_000)

    :ok =
      FluxTextToSpeechSocket.send_control(
        socket,
        FluxTextToSpeech.encode_speak("Hello from the Vxpipe streaming audio test.")
      )

    :ok = FluxTextToSpeechSocket.send_control(socket, FluxTextToSpeech.encode_flush())

    assert %Signal{kind: :speech_started, provider_speech_id: speech_id} =
             await_control(socket, :speech_started, 10_000)

    assert is_binary(speech_id)
    {audio_bytes, completed} = await_audio_and_completion(socket, speech_id, 0, 20_000)
    assert audio_bytes > 0
    assert %Signal{kind: :speech_completed, provider_speech_id: ^speech_id} = completed
  end

  defp await_control(socket, kind, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_control(socket, kind, deadline)
  end

  defp do_await_control(socket, kind, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:vxpipe_tts_transport, ^socket, {:control, payload}} ->
        case FluxTextToSpeech.decode(payload) do
          {:ok, %Signal{kind: ^kind} = signal} -> signal
          {:ok, %Signal{kind: :failed, provider_code: code}} -> flunk("Flux TTS failed: #{code}")
          _other -> do_await_control(socket, kind, deadline)
        end

      {:vxpipe_tts_transport, ^socket, {:closed, reason}} ->
        flunk("Flux TTS closed before #{kind}: #{inspect(reason)}")
    after
      remaining -> flunk("timed out waiting for Flux TTS #{kind}")
    end
  end

  defp await_audio_and_completion(socket, speech_id, audio_bytes, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_audio_and_completion(socket, speech_id, audio_bytes, deadline)
  end

  defp do_await_audio_and_completion(socket, speech_id, audio_bytes, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:vxpipe_tts_transport, ^socket, {:audio, reference, audio}} ->
        assert {:audio, audio} = FluxTextToSpeech.decode_audio(audio)
        send(socket, {:vxpipe_tts_audio_result, self(), reference, :ok})
        do_await_audio_and_completion(socket, speech_id, audio_bytes + byte_size(audio), deadline)

      {:vxpipe_tts_transport, ^socket, {:control, payload}} ->
        case FluxTextToSpeech.decode(payload) do
          {:ok, %Signal{kind: :speech_completed, provider_speech_id: ^speech_id} = signal} ->
            {audio_bytes, signal}

          {:ok, %Signal{kind: :failed, provider_code: code}} ->
            flunk("Flux TTS failed: #{code}")

          _other ->
            do_await_audio_and_completion(socket, speech_id, audio_bytes, deadline)
        end

      {:vxpipe_tts_transport, ^socket, {:closed, reason}} ->
        flunk("Flux TTS closed before completion: #{inspect(reason)}")
    after
      remaining -> flunk("timed out waiting for Flux TTS audio completion")
    end
  end
end
