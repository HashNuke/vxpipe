defmodule Vxpipe.CallEngine.TestDeepgramAudioConfirmation do
  @moduledoc "Finite, test-only recognition of captured provider PCM without wording hints."

  def transcribe(pcm, sample_rate, api_key, options)
      when is_binary(pcm) and byte_size(pcm) in 2..2_097_152 and
             rem(byte_size(pcm), 2) == 0 and is_integer(sample_rate) and sample_rate > 0 do
    timeout = min(Keyword.fetch!(options, :timeout_ms), 10_000)

    request_options =
      [
        headers: [
          {"authorization", "Token " <> api_key},
          {"content-type", "application/octet-stream"}
        ],
        params: [
          model: "nova-3",
          encoding: "linear16",
          sample_rate: sample_rate,
          channels: 1,
          language: "en"
        ],
        body: pcm,
        retry: false,
        receive_timeout: timeout,
        connect_options: [timeout: min(timeout, 5_000)]
      ] ++ Keyword.take(options, [:plug])

    case Req.post("https://api.deepgram.com/v1/listen", request_options) do
      {:ok, %Req.Response{status: 200, body: %{"results" => %{"channels" => [channel]}}}} ->
        case channel do
          %{"alternatives" => [%{"transcript" => text} | _]}
          when is_binary(text) and text != "" ->
            {:ok, text}

          _invalid ->
            {:error, :recognition_failed}
        end

      _failure ->
        {:error, :recognition_failed}
    end
  rescue
    _error -> {:error, :recognition_failed}
  end
end
