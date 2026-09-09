defmodule Vxpipe.Calls.VariableSnapshotHistory do
  @moduledoc "Tenant-scoped persisted Call Variables history and its latest snapshot."

  alias Vxpipe.Calls.VariableSnapshot

  @enforce_keys [:snapshots, :latest]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          snapshots: [VariableSnapshot.t()],
          latest: nil | VariableSnapshot.t()
        }
end
