defmodule Vxpipe.Providers.Google.TTSRequest do
  @moduledoc false

  alias Vxpipe.Providers.Google.{TTS, TTSStream}

  def run(%TTS{} = config, text, consume) when is_function(consume, 1) do
    into = fn {:data, chunk}, {request, response} ->
      state = Req.Response.get_private(response, :google_tts_stream, TTSStream.new())

      case TTSStream.feed(state, chunk) do
        {:ok, state, events} ->
          response = Req.Response.put_private(response, :google_tts_stream, state)

          case consume_events(events, consume) do
            :ok ->
              {:cont, {request, response}}

            {:error, reason} ->
              response = Req.Response.put_private(response, :google_tts_error, reason)
              {:halt, {request, response}}
          end

        {:error, reason} ->
          response = Req.Response.put_private(response, :google_tts_error, reason)
          {:halt, {request, response}}
      end
    end

    case Req.post(config.endpoint, TTS.request_options(config, text, into)) do
      {:ok, %Req.Response{status: 200} = response} ->
        case Req.Response.get_private(response, :google_tts_error) do
          nil ->
            response
            |> Req.Response.get_private(:google_tts_stream, TTSStream.new())
            |> TTSStream.finish()

          _error ->
            {:error, :provider_unavailable}
        end

      _failure ->
        {:error, :provider_unavailable}
    end
  rescue
    _exception -> {:error, :provider_unavailable}
  catch
    _, _reason -> {:error, :provider_unavailable}
  end

  defp consume_events(events, consume) do
    Enum.reduce_while(events, :ok, fn
      {:audio, audio}, :ok ->
        case consume.(audio) do
          :ok -> {:cont, :ok}
          _error -> {:halt, {:error, :consumer_unavailable}}
        end

      :completed, :ok ->
        {:cont, :ok}
    end)
  end
end
