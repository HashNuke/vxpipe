defmodule Vxpipe.Calls.TelephonyRoute do
  @moduledoc "Tenant-scoped deployment metadata for one inbound telephony participant."

  @enforce_keys [
    :tenant_key,
    :definition_id,
    :definition_revision,
    :participant_ref,
    :service,
    :number,
    :published_at
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_key: String.t(),
          definition_id: String.t(),
          definition_revision: pos_integer(),
          participant_ref: String.t(),
          service: String.t(),
          number: String.t(),
          published_at: nil | DateTime.t()
        }
end
