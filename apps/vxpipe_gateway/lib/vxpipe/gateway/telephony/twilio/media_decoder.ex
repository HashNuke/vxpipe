defmodule Vxpipe.Gateway.Telephony.Twilio.MediaDecoder do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.Event

  alias Vxpipe.Gateway.Telephony.Twilio.{
    MediaControlDecoder,
    MediaPacketDecoder,
    MediaStartDecoder
  }

  @maximum_message_bytes 131_072

  @spec decode(keyword(), binary()) ::
          {:ok, Event.t()} | :ignore | {:error, :invalid_twilio_media_message}
  def decode(options, message)
      when is_list(options) and is_binary(message) and
             byte_size(message) <= @maximum_message_bytes do
    with {:ok, decoded} <- JSON.decode(message) do
      decode_message(options, decoded)
    else
      _invalid -> invalid()
    end
  end

  def decode(_options, _message), do: invalid()

  defp decode_message(options, %{"event" => "start"} = message),
    do: MediaStartDecoder.decode(options, message)

  defp decode_message(options, %{"event" => "media"} = message),
    do: MediaPacketDecoder.decode(options, message)

  defp decode_message(options, %{"event" => "dtmf"} = message),
    do: MediaControlDecoder.dtmf(options, message)

  defp decode_message(options, %{"event" => "mark"} = message),
    do: MediaControlDecoder.mark(options, message)

  defp decode_message(options, %{"event" => "stop"} = message),
    do: MediaControlDecoder.stop(options, message)

  defp decode_message(_options, %{"event" => "connected"} = message),
    do: MediaControlDecoder.connected(message)

  defp decode_message(_options, %{"event" => event}) when is_binary(event), do: :ignore
  defp decode_message(_options, _message), do: invalid()
  defp invalid, do: {:error, :invalid_twilio_media_message}
end
