defmodule Vxpipe.Providers.Telnyx.WebhookDecoder do
  @moduledoc false

  alias Vxpipe.CallEngine.Telephony.{Event, Webhook}
  alias Vxpipe.Providers.Telnyx.ClientState

  @maximum_event_type_bytes 128
  @maximum_event_id_bytes 128
  @maximum_connection_id_bytes 128
  @maximum_call_control_id_bytes 1_024
  @maximum_leg_id_bytes 128
  @maximum_session_id_bytes 128
  @maximum_phone_address_bytes 128
  @maximum_hangup_cause_bytes 128

  @spec decode(Webhook.t()) :: {:ok, Event.t()} | :ignore | {:error, :invalid_telnyx_webhook}
  def decode(%Webhook{body: body}) when is_binary(body) do
    with {:ok, decoded} <- JSON.decode(body),
         {:ok, data, event_type} <- envelope(decoded) do
      decode_event(event_type, data)
    else
      _invalid -> invalid()
    end
  end

  defp envelope(%{
         "data" => %{"record_type" => "event", "event_type" => event_type} = data
       }) do
    with {:ok, event_type} <- bounded_string(event_type, @maximum_event_type_bytes) do
      {:ok, data, event_type}
    end
  end

  defp envelope(_invalid), do: :error

  defp decode_event("call.initiated", %{"payload" => %{"direction" => "incoming"}} = data) do
    with {:ok, payload} <- payload(data),
         {:ok, from} <- bounded_field(payload, "from", @maximum_phone_address_bytes),
         {:ok, to} <- bounded_field(payload, "to", @maximum_phone_address_bytes) do
      build_event(:incoming, data, from: from, to: to)
    else
      _invalid -> invalid()
    end
  end

  defp decode_event("call.initiated", %{"payload" => %{"direction" => "outgoing"}} = data) do
    with {:ok, payload} <- payload(data),
         {:ok, from} <- bounded_field(payload, "from", @maximum_phone_address_bytes),
         {:ok, to} <- bounded_field(payload, "to", @maximum_phone_address_bytes),
         {:ok, leg_id} <- ClientState.decode(Map.get(payload, "client_state")) do
      build_event(:outgoing, data, from: from, to: to, leg_id: leg_id)
    else
      _invalid -> invalid()
    end
  end

  defp decode_event("call.initiated", _invalid), do: invalid()

  defp decode_event("call.answered", data), do: build_event(:answered, data)

  defp decode_event("call.dtmf.received", data) do
    with {:ok, payload} <- payload(data),
         {:ok, digit} <- bounded_field(payload, "digit", 1) do
      build_event(:dtmf, data, digit: digit)
    else
      _invalid -> invalid()
    end
  end

  defp decode_event("call.machine.detection.ended" = event_type, data),
    do: decode_answering_machine(event_type, data)

  defp decode_event("call.machine.premium.detection.ended" = event_type, data),
    do: decode_answering_machine(event_type, data)

  defp decode_event("call.hangup", data) do
    with {:ok, payload} <- payload(data),
         {:ok, cause} <- bounded_field(payload, "hangup_cause", @maximum_hangup_cause_bytes) do
      build_event(:ended, data, end_reason: end_reason(cause))
    else
      _invalid -> invalid()
    end
  end

  defp decode_event(_unconsumed_event, _data), do: :ignore

  defp decode_answering_machine(event_type, data) do
    with {:ok, payload} <- payload(data),
         {:ok, result} <- answering_machine_result(event_type, Map.get(payload, "result")) do
      build_event(:answering_machine, data, answering_machine: result)
    else
      _invalid -> invalid()
    end
  end

  defp build_event(kind, data, attributes \\ []) do
    with {:ok, payload} <- payload(data),
         {:ok, event_id} <- bounded_field(data, "id", @maximum_event_id_bytes),
         {:ok, occurred_at} <- occurred_at(Map.get(data, "occurred_at")),
         {:ok, connection_id} <-
           bounded_field(payload, "connection_id", @maximum_connection_id_bytes),
         {:ok, call_control_id} <-
           bounded_field(payload, "call_control_id", @maximum_call_control_id_bytes),
         {:ok, call_leg_id} <- bounded_field(payload, "call_leg_id", @maximum_leg_id_bytes),
         {:ok, call_session_id} <-
           bounded_field(payload, "call_session_id", @maximum_session_id_bytes) do
      event =
        struct!(
          Event,
          Keyword.merge(
            [
              kind: kind,
              provider: :telnyx,
              provider_event_id: event_id,
              provider_connection_id: connection_id,
              provider_call_control_id: call_control_id,
              provider_call_leg_id: call_leg_id,
              provider_call_session_id: call_session_id,
              occurred_at: occurred_at,
              occurred_at_provenance: :provider_reported
            ],
            attributes
          )
        )

      if Event.valid?(event), do: {:ok, event}, else: invalid()
    else
      _invalid -> invalid()
    end
  end

  defp payload(%{"payload" => payload}) when is_map(payload), do: {:ok, payload}
  defp payload(_invalid), do: :error

  defp bounded_field(map, key, maximum_bytes) do
    bounded_string(Map.get(map, key), maximum_bytes)
  end

  defp bounded_string(value, maximum_bytes)
       when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= maximum_bytes,
       do: {:ok, value}

  defp bounded_string(_invalid, _maximum_bytes), do: :error

  defp occurred_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, timestamp, _offset} -> {:ok, timestamp}
      {:error, _reason} -> :error
    end
  end

  defp occurred_at(_invalid), do: :error

  defp answering_machine_result("call.machine.detection.ended", "human"), do: {:ok, :human}
  defp answering_machine_result("call.machine.detection.ended", "machine"), do: {:ok, :machine}
  defp answering_machine_result("call.machine.detection.ended", "not_sure"), do: {:ok, :unknown}

  defp answering_machine_result("call.machine.premium.detection.ended", result)
       when result in ["human_residence", "human_business"],
       do: {:ok, :human}

  defp answering_machine_result("call.machine.premium.detection.ended", result)
       when result in ["machine", "silence", "fax_detected"],
       do: {:ok, :machine}

  defp answering_machine_result("call.machine.premium.detection.ended", "not_sure"),
    do: {:ok, :unknown}

  defp answering_machine_result(_event_type, _invalid), do: :error

  defp end_reason(cause) when cause in ["normal_clearing", "originator_cancel", "call_rejected"],
    do: :hangup

  defp end_reason("user_busy"), do: :busy
  defp end_reason("no_answer"), do: :no_answer
  defp end_reason("timeout"), do: :timeout
  defp end_reason(_provider_failure), do: :failed

  defp invalid, do: {:error, :invalid_telnyx_webhook}
end
