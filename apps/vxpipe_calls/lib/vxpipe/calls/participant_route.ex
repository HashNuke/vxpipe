defmodule Vxpipe.Calls.ParticipantRoute do
  @moduledoc "Tenant-scoped deployment metadata for one web participant."

  @enforce_keys [
    :key,
    :tenant_key,
    :call_spec_id,
    :call_spec_revision,
    :participant_ref,
    :published_at
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          key: String.t(),
          tenant_key: String.t(),
          call_spec_id: String.t(),
          call_spec_revision: pos_integer(),
          participant_ref: String.t(),
          published_at: nil | DateTime.t()
        }
end
