defmodule Vxpipe.Gateway.RTVI.Codec do
  @moduledoc false

  @label "rtvi-ai"
  @protocol_version "2.1.0"
  @protocol_major 2

  @spec handle(binary()) :: :ignore | {:reply, binary()}
  def handle(payload) when is_binary(payload) do
    with {:ok, message} when is_map(message) <- JSON.decode(payload) do
      handle_message(message)
    else
      _error -> :ignore
    end
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
    JSON.encode!(%{
      "id" => id,
      "label" => @label,
      "type" => "error-response",
      "data" => %{
        "error" =>
          "RTVI version #{version} is not compatible with server protocol #{@protocol_version}."
      }
    })
  end

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
