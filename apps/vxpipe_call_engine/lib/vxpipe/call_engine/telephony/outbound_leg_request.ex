defmodule Vxpipe.CallEngine.Telephony.OutboundLegRequest do
  @moduledoc "Exact room destination authorized for one provider-neutral outbound phone leg."

  @phone_number ~r/\A\+[1-9][0-9]{1,14}\z/

  @derive {Inspect,
           only: [
             :tenant_id,
             :actor_id,
             :call_id,
             :room_id,
             :incarnation_id,
             :participant_id,
             :service_id
           ]}
  @enforce_keys [
    :tenant_id,
    :actor_id,
    :call_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :service_id,
    :to
  ]
  defstruct @enforce_keys ++
              [service_reference: nil, purpose: :transfer, room_owner: nil, attempt_id: nil]

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          actor_id: String.t(),
          call_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          participant_id: String.t(),
          service_id: String.t(),
          service_reference: Vxpipe.CallEngine.Telephony.ServiceReference.t() | nil,
          purpose: :initial | :transfer,
          room_owner: pid() | nil,
          attempt_id: reference() | nil,
          to: String.t()
        }

  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = request) do
    Enum.all?(
      [
        request.tenant_id,
        request.actor_id,
        request.call_id,
        request.room_id,
        request.incarnation_id,
        request.participant_id,
        request.service_id
      ],
      &present?/1
    ) and phone_number?(request.to) and valid_purpose?(request)
  end

  defp valid_purpose?(%{purpose: :transfer}), do: true

  defp valid_purpose?(%{purpose: :initial, room_owner: owner, attempt_id: attempt}),
    do: is_pid(owner) and is_reference(attempt)

  defp valid_purpose?(_request), do: false

  defp phone_number?(value), do: is_binary(value) and Regex.match?(@phone_number, value)
  defp present?(value), do: is_binary(value) and value != ""
end
