defmodule Vxpipe.Calls.InspectionRepository do
  @moduledoc "Persistence port for bounded, tenant-scoped call inspection reads."

  alias Vxpipe.Calls.{CallFact, CallListCursor, CallSummary, HistoryCursor, VariableSnapshot}

  @type context :: term()

  @callback list_calls(context(), String.t(), pos_integer(), CallListCursor.t() | nil) ::
              {:ok, [CallSummary.t()]} | {:error, term()}

  @callback fetch_call(context(), String.t(), String.t()) ::
              {:ok, CallSummary.t()} | {:error, :call_not_found | term()}

  @callback list_history_records(
              context(),
              String.t(),
              String.t(),
              pos_integer(),
              HistoryCursor.t() | nil
            ) :: {:ok, [CallFact.t() | VariableSnapshot.t()]} | {:error, term()}
end
