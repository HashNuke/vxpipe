defmodule Vxpipe.Calls.ArchiveRepository do
  @moduledoc "Persistence port for private call-history projections."

  alias Vxpipe.Calls.{CallFact, VariableSnapshot, VariableSnapshotHistory}

  @type context :: term()

  @callback store_variable_snapshot(context(), VariableSnapshot.t()) ::
              {:ok, VariableSnapshot.t()} | {:error, term()}

  @callback fetch_variable_snapshots(context(), String.t(), String.t()) ::
              {:ok, VariableSnapshotHistory.t()} | {:error, term()}

  @callback store_call_fact(context(), CallFact.t()) ::
              {:ok, CallFact.t()} | {:error, term()}

  @callback fetch_call_facts(context(), String.t(), String.t()) ::
              {:ok, [CallFact.t()]} | {:error, term()}
end
