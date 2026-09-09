defmodule Vxpipe.Calls.ArchiveRepository do
  @moduledoc "Persistence port for private call-history projections."

  alias Vxpipe.Calls.{VariableSnapshot, VariableSnapshotHistory}

  @type context :: term()

  @callback store_variable_snapshot(context(), VariableSnapshot.t()) ::
              {:ok, VariableSnapshot.t()} | {:error, term()}

  @callback fetch_variable_snapshots(context(), String.t(), String.t()) ::
              {:ok, VariableSnapshotHistory.t()} | {:error, term()}
end
