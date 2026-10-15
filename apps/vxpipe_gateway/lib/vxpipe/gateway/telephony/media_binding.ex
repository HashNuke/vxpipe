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
  defstruct @enforce_keys ++ [cleanup_binding: nil]

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
          provider_call_session_id: nil | String.t(),
          client_state_leg_id: String.t(),
          leg: pid(),
          cleanup_binding: map() | nil
        }

  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = binding) do
    binding.provider in [:telnyx, :twilio] and is_pid(binding.leg) and
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
          binding.client_state_leg_id
        ],
        &present?/1
      ) and optional_identifier?(binding.provider_call_session_id) and
      match?({:ok, _}, cleanup_binding(binding))
  end

  @doc false
  def cleanup_binding(%__MODULE__{cleanup_binding: nil}), do: {:ok, nil}

  def cleanup_binding(%__MODULE__{
        tenant_id: tenant,
        call_id: call,
        room_id: room,
        incarnation_id: incarnation,
        cleanup_binding:
          %{tenant_key: tenant, call_id: call, room_id: room, incarnation_id: incarnation} =
            binding
      })
      when map_size(binding) == 4 and is_binary(call) and byte_size(call) in 1..128,
      do: {:ok, binding}

  def cleanup_binding(%__MODULE__{}), do: {:error, :invalid_cleanup_binding}

  @spec matches_event?(t(), Vxpipe.CallEngine.Telephony.Event.t()) :: boolean()
  def matches_event?(%__MODULE__{} = binding, %Vxpipe.CallEngine.Telephony.Event{} = event) do
    Vxpipe.CallEngine.Telephony.Event.valid?(event) and event.provider == binding.provider and
      event.provider_connection_id == binding.provider_connection_id and
      event.provider_call_control_id == binding.provider_call_control_id and
      event.provider_call_leg_id == binding.provider_call_leg_id and
      event.provider_call_session_id == binding.provider_call_session_id
  end

  defp present?(value), do: is_binary(value) and value != ""
  defp optional_identifier?(nil), do: true
  defp optional_identifier?(value), do: present?(value)
end
