defmodule Vxpipe.Gateway.Telephony.Twilio.MediaStartDecoder do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Gateway.Telephony.Twilio.{Identifier, MediaFields}

  @spec decode(keyword(), map()) :: {:ok, Event.t()} | {:error, :invalid_twilio_media_message}
  def decode(options, %{"start" => start} = message) when is_map(start) do
    with {:ok, stream_id} <- MediaFields.string(message, "streamSid"),
         true <- Identifier.stream_sid?(stream_id),
         {:ok, nested_stream_id} <- MediaFields.string(start, "streamSid"),
         true <- nested_stream_id == stream_id,
         :ok <- MediaFields.optional_expected(options, :stream_id, stream_id),
         {:ok, account_sid} <- MediaFields.string(start, "accountSid"),
         :ok <- MediaFields.required_expected(options, :provider_connection_id, account_sid),
         {:ok, call_sid} <- MediaFields.string(start, "callSid"),
         :ok <- MediaFields.required_expected(options, :provider_call_control_id, call_sid),
         :ok <- MediaFields.required_expected(options, :provider_call_leg_id, call_sid),
         ["inbound"] <- Map.get(start, "tracks"),
         :ok <- media_format(Map.get(start, "mediaFormat")),
         {:ok, identity} <- MediaFields.identity(options) do
      event = struct!(Event, Map.merge(identity, %{kind: :media_started, stream_id: stream_id}))
      {:ok, event}
    else
      _invalid -> invalid()
    end
  end

  def decode(_options, _message), do: invalid()

  defp media_format(%{
         "encoding" => "audio/x-mulaw",
         "sampleRate" => 8_000,
         "channels" => 1
       }),
       do: :ok

  defp media_format(_invalid), do: :error
  defp invalid, do: {:error, :invalid_twilio_media_message}
end
