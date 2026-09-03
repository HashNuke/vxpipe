defmodule Vxpipe.Gateway.RTVI.Codec do
  @moduledoc false

  alias Vxpipe.CallEngine.Event.TextOutput

  @label "rtvi-ai"
  @protocol_version "2.1.0"
  @protocol_major 2

  @type send_text :: %{
          id: String.t(),
          content: String.t(),
          run_immediately: boolean(),
          audio_response: boolean()
        }

  @spec handle(binary()) ::
          :ignore | {:reply, binary()} | {:command, {:send_text, send_text()}}
  def handle(payload) when is_binary(payload) do
    with {:ok, message} when is_map(message) <- JSON.decode(payload) do
      handle_message(message)
    else
      _error -> :ignore
    end
  end

  @spec encode_event(TextOutput.t()) :: {:ok, binary()}
  def encode_event(%TextOutput{} = event) do
    {:ok,
     JSON.encode!(%{
       "id" => event.id,
       "label" => @label,
       "type" => "bot-output",
       "data" => %{
         "text" => event.text,
         "aggregated_by" => aggregation(event.aggregated_by),
         "segment_id" => event.sequence,
         "will_be_spoken" => event.will_be_spoken
       }
     })}
  end

  @spec encode_error_response(String.t(), String.t()) :: binary()
  def encode_error_response(id, message) when is_binary(id) and is_binary(message) do
    error_response(id, message)
  end

  defp handle_message(%{
         "id" => id,
         "label" => @label,
         "type" => "client-ready",
         "data" => %{"version" => version}
       })
       when is_binary(id) and is_binary(version) do
    case parse_version(version) do
      {:ok, {@protocol_major, _minor, _patch}} -> {:reply, bot_ready(id)}
      _unsupported_or_invalid -> {:reply, incompatible_version(id, version)}
    end
  end

  defp handle_message(%{
         "id" => id,
         "label" => @label,
         "type" => "send-text",
         "data" => %{"content" => content} = data
       })
       when is_binary(id) and is_binary(content) do
    case send_text_options(Map.get(data, "options", %{})) do
      {:ok, options} ->
        {:command,
         {:send_text,
          %{
            id: id,
            content: content,
            run_immediately: options.run_immediately,
            audio_response: options.audio_response
          }}}

      :error ->
        {:reply, error_response(id, "The send-text options are invalid.")}
    end
  end

  defp handle_message(%{"id" => id, "label" => @label, "type" => "send-text"})
       when is_binary(id) do
    {:reply, error_response(id, "The send-text content is invalid.")}
  end

  defp handle_message(_message), do: :ignore

  defp bot_ready(id) do
    JSON.encode!(%{
      "id" => id,
      "label" => @label,
      "type" => "bot-ready",
      "data" => %{
        "version" => @protocol_version,
        "about" => %{
          "library" => "vxpipe",
          "library_version" => gateway_version()
        }
      }
    })
  end

  defp incompatible_version(id, version) do
    error_response(
      id,
      "RTVI version #{version} is not compatible with server protocol #{@protocol_version}."
    )
  end

  defp error_response(id, message) do
    JSON.encode!(%{
      "id" => id,
      "label" => @label,
      "type" => "error-response",
      "data" => %{"error" => message}
    })
  end

  defp send_text_options(options) when is_map(options) do
    with {:ok, run_immediately} <- optional_boolean(options, "run_immediately", true),
         {:ok, audio_response} <- optional_boolean(options, "audio_response", true) do
      {:ok, %{run_immediately: run_immediately, audio_response: audio_response}}
    else
      :error -> :error
    end
  end

  defp send_text_options(_options), do: :error

  defp optional_boolean(options, key, default) do
    case Map.get(options, key, default) do
      value when is_boolean(value) -> {:ok, value}
      _invalid -> :error
    end
  end

  defp aggregation(:sentence), do: "sentence"

  defp parse_version(version) do
    with [major, minor, patch] <- String.split(version, "."),
         {major, ""} <- Integer.parse(major),
         {minor, ""} <- Integer.parse(minor),
         {patch, ""} <- Integer.parse(patch),
         true <- major >= 0 and minor >= 0 and patch >= 0 do
      {:ok, {major, minor, patch}}
    else
      _invalid -> :error
    end
  end

  defp gateway_version do
    :vxpipe_gateway
    |> Application.spec(:vsn)
    |> to_string()
  end
end
