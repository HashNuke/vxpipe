defmodule Vxpipe.Calls.TelephonyAdmissionClaim do
  @moduledoc "An atomically claimed inbound provider leg and its pinned call."

  alias Vxpipe.Calls.PreparedCall
  alias Vxpipe.CallEngine.Telephony.ServiceReference

  @derive {Inspect,
           only: [
             :call,
             :participant_ref,
             :participant_id,
             :provider,
             :service,
             :service_id,
             :accepted_at
           ]}
  @enforce_keys [
    :call,
    :participant_ref,
    :participant_id,
    :provider,
    :service,
    :service_id,
    :provider_event_id,
    :provider_connection_id,
    :provider_call_control_id,
    :provider_call_leg_id,
    :provider_call_session_id,
    :accepted_at
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          call: PreparedCall.t(),
          participant_ref: String.t(),
          participant_id: String.t(),
          provider: atom(),
          service: String.t(),
          service_id: String.t() | nil,
          provider_event_id: String.t(),
          provider_connection_id: String.t(),
          provider_call_control_id: String.t(),
          provider_call_leg_id: String.t(),
          provider_call_session_id: nil | String.t(),
          accepted_at: DateTime.t()
        }

  @doc "Checks the claim against the immutable prepared entry service before using its authority."
  def valid_service?(%__MODULE__{service_id: id, provider: provider} = claim)
      when is_binary(id) and provider in [:telnyx, :twilio] do
    case Map.get(claim.call.plan.participants, claim.participant_ref) do
      %{participant_id: participant_id, telephony_service: %ServiceReference{} = reference} ->
        claim.call.entry_caller == claim.participant_ref and
          claim.call.tenant_key == claim.call.plan.tenant_id and
          participant_id == claim.participant_id and reference.tenant_id == claim.call.tenant_key and
          reference.service_id == id and reference.name == claim.service and
          reference.provider == Atom.to_string(provider) and
          reference.provider_connection_id == claim.provider_connection_id

      _unbound ->
        false
    end
  end

  def valid_service?(_claim), do: false

  @doc "Compares stable carrier identity; retry-generated call and participant IDs are not identity."
  def same_leg?(%__MODULE__{} = left, %__MODULE__{} = right) do
    left.call.tenant_key == right.call.tenant_key and
      Enum.all?(
        [
          :service_id,
          :service,
          :provider,
          :provider_connection_id,
          :provider_call_control_id,
          :provider_call_leg_id,
          :provider_call_session_id
        ],
        &(Map.fetch!(left, &1) == Map.fetch!(right, &1))
      )
  end
end
