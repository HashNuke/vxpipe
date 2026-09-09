defmodule Vxpipe.Calls.ParticipantRoute do
  @moduledoc "Tenant-scoped deployment metadata for one web participant."

  @enforce_keys [
    :key,
    :tenant_key,
    :definition_id,
    :definition_revision,
    :participant_ref,
    :published_at
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          key: String.t(),
          tenant_key: String.t(),
          definition_id: String.t(),
          definition_revision: pos_integer(),
          participant_ref: String.t(),
          published_at: nil | DateTime.t()
        }
end
