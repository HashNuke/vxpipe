defmodule Vxpipe.CallEngine.TestGoogleTTSRequest do
  @moduledoc false

  def run(config, text, consume) do
    send(config.endpoint, {:test_google_tts_started, self(), text})
    loop(config.endpoint, consume)
  end

  defp loop(observer, consume) do
    receive do
      {:audio, audio} ->
        result = consume.(audio)
        send(observer, {:test_google_tts_audio_consumed, self(), result})
        if result == :ok, do: loop(observer, consume), else: result

      :complete ->
        :ok

      :fail ->
        {:error, :provider_unavailable}
    end
  end
end
