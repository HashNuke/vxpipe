defmodule Vxpipe.Calls.TelephonyRoute do
  @moduledoc "Tenant-scoped deployment metadata for one inbound telephony participant."

  @enforce_keys [
    :tenant_key,
    :call_spec_id,
    :call_spec_revision,
    :participant_ref,
    :service,
    :number,
    :published_at
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_key: String.t(),
          call_spec_id: String.t(),
          call_spec_revision: pos_integer(),
          participant_ref: String.t(),
          service: String.t(),
          number: String.t(),
          published_at: nil | DateTime.t()
        }
end
