defmodule Vxpipe.Calls.InspectionRepository do
  @moduledoc "Persistence port for bounded, tenant-scoped call inspection reads."

  alias Vxpipe.Calls.{CallListCursor, CallSummary}

  @type context :: term()

  @callback list_calls(context(), String.t(), pos_integer(), CallListCursor.t() | nil) ::
              {:ok, [CallSummary.t()]} | {:error, term()}
end
