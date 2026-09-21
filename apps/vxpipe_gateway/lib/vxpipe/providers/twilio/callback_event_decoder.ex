defmodule Vxpipe.Providers.Twilio.CallbackEventDecoder do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Providers.Twilio.Identifier

  @leg_id ~r/\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/

  @spec decode(keyword(), integer(), String.t(), map()) ::
          {:ok, Event.t()} | :ignore | {:error, :invalid_twilio_webhook}
  def decode(options, received_at, leg_id, %{
        "AccountSid" => account_sid,
        "AnsweredBy" => answered_by,
        "CallSid" => call_sid
      }) do
    with :ok <- common(options, received_at, leg_id, account_sid, call_sid),
         {:ok, result} <- answering_machine_result(answered_by),
         {:ok, occurred_at} <- DateTime.from_unix(received_at) do
      build_event(:answering_machine, account_sid, call_sid, leg_id, occurred_at,
        provider_event_id: "#{call_sid}:amd:#{answered_by}",
        answering_machine: result
      )
    else
      _invalid -> invalid()
    end
  end

  def decode(options, received_at, leg_id, %{
        "AccountSid" => account_sid,
        "CallSid" => call_sid,
        "CallStatus" => status,
        "Direction" => "outbound-api",
        "From" => from,
        "SequenceNumber" => sequence,
        "To" => to
      }) do
    with :ok <- common(options, received_at, leg_id, account_sid, call_sid),
         true <- present?(from) and present?(to),
         {:ok, sequence_number} <- sequence_number(sequence),
         {:ok, occurred_at} <- DateTime.from_unix(received_at),
         {:ok, kind, attributes} <- status(status) do
      build_event(
        kind,
        account_sid,
        call_sid,
        leg_id,
        occurred_at,
        Keyword.merge(
          [
            provider_event_id: "#{call_sid}:status:#{sequence_number}",
            sequence_number: sequence_number,
            from: from,
            to: to
          ],
          attributes
        )
      )
    else
      :ignore -> :ignore
      _invalid -> invalid()
    end
  end

  def decode(_options, _received_at, _leg_id, _parameters), do: invalid()

  defp common(options, received_at, leg_id, account_sid, call_sid) do
    if Keyword.get(options, :account_sid) == account_sid and is_integer(received_at) and
         received_at >= 0 and Identifier.account_sid?(account_sid) and
         Identifier.call_sid?(call_sid) and valid_leg_id?(leg_id),
       do: :ok,
       else: :error
  end

  defp build_event(kind, account_sid, call_sid, leg_id, occurred_at, attributes) do
    event =
      struct!(
        Event,
        Keyword.merge(
          [
            kind: kind,
            provider: :twilio,
            provider_connection_id: account_sid,
            provider_call_control_id: call_sid,
            provider_call_leg_id: call_sid,
            provider_call_session_id: nil,
            leg_id: leg_id,
            occurred_at: occurred_at,
            occurred_at_provenance: :locally_measured
          ],
          attributes
        )
      )

    if Event.valid?(event), do: {:ok, event}, else: invalid()
  end

  defp status(value) when value in ["initiated", "ringing"], do: {:ok, :outgoing, []}
  defp status("in-progress"), do: {:ok, :answered, []}
  defp status("completed"), do: {:ok, :ended, end_reason: :hangup}
  defp status("canceled"), do: {:ok, :ended, end_reason: :hangup}
  defp status("busy"), do: {:ok, :ended, end_reason: :busy}
  defp status("no-answer"), do: {:ok, :ended, end_reason: :no_answer}
  defp status("failed"), do: {:ok, :ended, end_reason: :failed}
  defp status(_unconsumed), do: :ignore

  defp answering_machine_result("human"), do: {:ok, :human}

  defp answering_machine_result(value)
       when value in [
              "machine_start",
              "machine_end_beep",
              "machine_end_silence",
              "machine_end_other",
              "fax"
            ],
       do: {:ok, :machine}

  defp answering_machine_result("unknown"), do: {:ok, :unknown}
  defp answering_machine_result(_invalid), do: :error

  defp sequence_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number >= 0 and number <= 2_147_483_647 -> {:ok, number}
      _invalid -> :error
    end
  end

  defp sequence_number(_invalid), do: :error
  defp valid_leg_id?(value) when is_binary(value), do: Regex.match?(@leg_id, value)
  defp valid_leg_id?(_invalid), do: false
  defp present?(value), do: is_binary(value) and byte_size(value) > 0 and byte_size(value) <= 128
  defp invalid, do: {:error, :invalid_twilio_webhook}
end
