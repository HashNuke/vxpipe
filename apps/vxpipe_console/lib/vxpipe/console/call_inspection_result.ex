defmodule Vxpipe.Console.CallInspectionResult do
  @moduledoc "Database records assembled for one versioned call-inspection response."

  alias Vxpipe.Calls.{CallHistory, CallSummary, DefinitionRevision, UsageReport}

  @enforce_keys [:call, :history, :definition, :usage]
  defstruct @enforce_keys

  @type availability(value) :: {:available, value} | {:unavailable, term()}

  @type t :: %__MODULE__{
          call: CallSummary.t(),
          history: CallHistory.t(),
          definition: availability(DefinitionRevision.t()),
          usage: availability(UsageReport.t())
        }
end
