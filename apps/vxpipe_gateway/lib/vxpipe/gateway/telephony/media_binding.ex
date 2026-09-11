defmodule Vxpipe.Gateway.Telephony.MediaBinding do
  @moduledoc "An exact live telephony leg authorized to claim one provider media socket."

  @derive {Inspect,
           only: [
             :provider,
             :service_id,
             :tenant_id,
             :call_id,
             :room_id,
             :incarnation_id,
             :participant_id,
             :provider_call_leg_id
           ]}
  @enforce_keys [
    :provider,
    :service_id,
    :ingress_key,
    :tenant_id,
    :call_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :provider_connection_id,
    :provider_call_control_id,
    :provider_call_leg_id,
    :provider_call_session_id,
    :client_state_leg_id,
    :leg
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          provider: atom(),
          service_id: String.t(),
          ingress_key: String.t(),
          tenant_id: String.t(),
          call_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          participant_id: String.t(),
          provider_connection_id: String.t(),
          provider_call_control_id: String.t(),
          provider_call_leg_id: String.t(),
          provider_call_session_id: String.t(),
          client_state_leg_id: String.t(),
          leg: pid()
        }

  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = binding) do
    binding.provider == :telnyx and is_pid(binding.leg) and
      Enum.all?(
        [
          binding.service_id,
          binding.ingress_key,
          binding.tenant_id,
          binding.call_id,
          binding.room_id,
          binding.incarnation_id,
          binding.participant_id,
          binding.provider_connection_id,
          binding.provider_call_control_id,
          binding.provider_call_leg_id,
          binding.provider_call_session_id,
          binding.client_state_leg_id
        ],
        &present?/1
      )
  end

  defp present?(value), do: is_binary(value) and value != ""
end
