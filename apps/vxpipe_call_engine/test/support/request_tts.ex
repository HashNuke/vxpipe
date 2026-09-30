defmodule Vxpipe.CallEngine.TestRequestTTS do
  @moduledoc false

  def run(config, text, consume) do
    send(config.endpoint, {:test_request_tts_started, self(), text})
    loop(config.endpoint, consume)
  end

  defp loop(observer, consume) do
    receive do
      {:audio, audio} ->
        result = consume.(audio)
        send(observer, {:test_request_tts_audio_consumed, self(), result})
        if result == :ok, do: loop(observer, consume), else: result

      :complete ->
        :ok

      :fail ->
        {:error, :provider_unavailable}
    end
  end
end
