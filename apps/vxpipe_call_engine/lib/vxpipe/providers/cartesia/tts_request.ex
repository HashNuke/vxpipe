defmodule Vxpipe.Providers.Cartesia.TTSRequest do
  @moduledoc false
  alias Vxpipe.CallEngine.Speech.PCMStream
  alias Vxpipe.Providers.Cartesia.TTS
  @content_types ["audio/pcm", "audio/raw", "audio/x-pcm", "application/octet-stream"]

  def run(%TTS{} = config, text, consume) when is_function(consume, 1) do
    into = fn {:data, chunk}, {request, response} ->
      state = Req.Response.get_private(response, :tts_pcm_stream, PCMStream.new())

      with true <- response.status == 200 and raw_pcm_response?(response),
           {:ok, state, chunks} <- PCMStream.feed(state, chunk),
           :ok <- consume_chunks(chunks, consume) do
        {:cont, {request, Req.Response.put_private(response, :tts_pcm_stream, state)}}
      else
        _failure -> {:halt, {request, Req.Response.put_private(response, :tts_error, true)}}
      end
    end

    case Req.post(config.endpoint, TTS.request_options(config, text, into)) do
      {:ok, %Req.Response{status: 200} = response} ->
        with true <- raw_pcm_response?(response),
             nil <- Req.Response.get_private(response, :tts_error),
             :ok <-
               PCMStream.finish(
                 Req.Response.get_private(response, :tts_pcm_stream, PCMStream.new())
               ) do
          :ok
        else
          _failure -> {:error, :provider_unavailable}
        end

      _failure ->
        {:error, :provider_unavailable}
    end
  rescue
    _exception -> {:error, :provider_unavailable}
  catch
    _, _reason -> {:error, :provider_unavailable}
  end

  defp raw_pcm_response?(response) do
    case Req.Response.get_header(response, "content-type") do
      [type | _] ->
        type
        |> String.split(";", parts: 2)
        |> List.first()
        |> String.trim()
        |> String.downcase()
        |> then(&(&1 in @content_types))

      [] ->
        false
    end
  end

  defp consume_chunks(chunks, consume) do
    Enum.reduce_while(chunks, :ok, fn audio, :ok ->
      case consume.(audio) do
        :ok -> {:cont, :ok}
        _failure -> {:halt, {:error, :consumer_unavailable}}
      end
    end)
  end
end
