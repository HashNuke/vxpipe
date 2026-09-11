defmodule Vxpipe.Gateway.Telephony.Twilio.TwiML do
  @moduledoc false

  @spec connect_stream(String.t()) :: {:ok, String.t()} | {:error, :invalid_twilio_media_url}
  def connect_stream(media_url) when is_binary(media_url) do
    case URI.parse(media_url) do
      %URI{scheme: "wss", host: host} when is_binary(host) and host != "" ->
        escaped = escape(media_url)

        {:ok,
         ~s(<?xml version="1.0" encoding="UTF-8"?><Response><Connect><Stream url="#{escaped}" /></Connect></Response>)}

      _invalid ->
        {:error, :invalid_twilio_media_url}
    end
  end

  def connect_stream(_invalid), do: {:error, :invalid_twilio_media_url}

  defp escape(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
