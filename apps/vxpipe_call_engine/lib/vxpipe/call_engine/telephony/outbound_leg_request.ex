defmodule Vxpipe.CallEngine.Telephony.OutboundLegRequest do
  @moduledoc "Exact room destination authorized for one provider-neutral outbound phone leg."

  @phone_number ~r/\A\+[1-9][0-9]{1,14}\z/

  @derive {Inspect,
           only: [
             :tenant_id,
             :call_id,
             :room_id,
             :incarnation_id,
             :participant_id,
             :service_id,
             :answering_machine_detection
           ]}
  @enforce_keys [
    :tenant_id,
    :call_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :service_id,
    :to,
    :answering_machine_detection
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          call_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          participant_id: String.t(),
          service_id: String.t(),
          to: String.t(),
          answering_machine_detection: :disabled | :detect
        }

  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = request) do
    Enum.all?(
      [
        request.tenant_id,
        request.call_id,
        request.room_id,
        request.incarnation_id,
        request.participant_id,
        request.service_id
      ],
      &present?/1
    ) and phone_number?(request.to) and
      request.answering_machine_detection in [:disabled, :detect]
  end

  defp phone_number?(value), do: is_binary(value) and Regex.match?(@phone_number, value)
  defp present?(value), do: is_binary(value) and value != ""
end
