defmodule Vxpipe.Gateway.Telephony.Twilio.WebhookDecoder do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.{Event, Webhook}
  alias Vxpipe.Gateway.Telephony.Twilio.Form

  @account_sid ~r/\AAC[0-9a-fA-F]{32}\z/
  @call_sid ~r/\ACA[0-9a-fA-F]{32}\z/

  @spec decode(keyword(), Webhook.t()) ::
          {:ok, Event.t()} | :ignore | {:error, :invalid_twilio_webhook}
  def decode(options, %Webhook{} = webhook) do
    with {:ok, parameters} <- Form.decode(webhook.body) do
      decode_parameters(options, webhook.received_at, parameters)
    else
      _invalid -> invalid()
    end
  end

  defp decode_parameters(options, received_at, %{
         "AccountSid" => account_sid,
         "CallSid" => call_sid,
         "CallStatus" => status,
         "Direction" => "inbound",
         "From" => from,
         "To" => to
       })
       when status in ["ringing", "in-progress"] do
    with :ok <- expected_account(options, account_sid),
         true <- Regex.match?(@account_sid, account_sid),
         true <- Regex.match?(@call_sid, call_sid),
         true <- present?(from) and present?(to),
         {:ok, occurred_at} <- DateTime.from_unix(received_at) do
      {:ok,
       %Event{
         kind: :incoming,
         provider: :twilio,
         provider_event_id: "#{call_sid}:incoming",
         provider_connection_id: account_sid,
         provider_call_control_id: call_sid,
         provider_call_leg_id: call_sid,
         provider_call_session_id: nil,
         occurred_at: occurred_at,
         from: from,
         to: to
       }}
    else
      _invalid -> invalid()
    end
  end

  defp decode_parameters(_options, _received_at, _parameters), do: invalid()

  defp expected_account(options, account_sid) do
    if Keyword.get(options, :account_sid) == account_sid, do: :ok, else: :error
  end

  defp present?(value), do: is_binary(value) and byte_size(value) > 0
  defp invalid, do: {:error, :invalid_twilio_webhook}
end
