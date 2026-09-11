defmodule Vxpipe.Calls.TelephonyAdmissionClaim do
  @moduledoc "An atomically claimed inbound provider leg and its pinned call."

  alias Vxpipe.Calls.PreparedCall

  @derive {Inspect,
           only: [
             :call,
             :participant_ref,
             :participant_id,
             :provider,
             :service,
             :accepted_at
           ]}
  @enforce_keys [
    :call,
    :participant_ref,
    :participant_id,
    :provider,
    :service,
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
          provider_event_id: String.t(),
          provider_connection_id: String.t(),
          provider_call_control_id: String.t(),
          provider_call_leg_id: String.t(),
          provider_call_session_id: nil | String.t(),
          accepted_at: DateTime.t()
        }
end
