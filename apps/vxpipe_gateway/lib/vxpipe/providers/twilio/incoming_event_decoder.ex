defmodule Vxpipe.Providers.Twilio.IncomingEventDecoder do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Providers.Twilio.Identifier

  @spec decode(keyword(), integer(), map()) ::
          {:ok, Event.t()} | {:error, :invalid_twilio_webhook}
  def decode(options, received_at, %{
        "AccountSid" => account_sid,
        "CallSid" => call_sid,
        "CallStatus" => status,
        "Direction" => "inbound",
        "From" => from,
        "To" => to
      })
      when status in ["ringing", "in-progress"] do
    with :ok <- expected_account(options, account_sid),
         true <- Identifier.account_sid?(account_sid),
         true <- Identifier.call_sid?(call_sid),
         true <- present?(from) and present?(to),
         {:ok, occurred_at} <- DateTime.from_unix(received_at) do
      event = %Event{
        kind: :incoming,
        provider: :twilio,
        provider_event_id: "#{call_sid}:incoming",
        provider_connection_id: account_sid,
        provider_call_control_id: call_sid,
        provider_call_leg_id: call_sid,
        provider_call_session_id: nil,
        occurred_at: occurred_at,
        occurred_at_provenance: :locally_measured,
        from: from,
        to: to
      }

      if Event.valid?(event), do: {:ok, event}, else: invalid()
    else
      _invalid -> invalid()
    end
  end

  def decode(_options, _received_at, _parameters), do: invalid()

  defp expected_account(options, account_sid) do
    if Keyword.get(options, :account_sid) == account_sid, do: :ok, else: :error
  end

  defp present?(value), do: is_binary(value) and byte_size(value) > 0
  defp invalid, do: {:error, :invalid_twilio_webhook}
end
