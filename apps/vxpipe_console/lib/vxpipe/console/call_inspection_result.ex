defmodule Vxpipe.Console.CallInspectionResult do
  @moduledoc "Database records assembled for one versioned call-inspection response."

  alias Vxpipe.Calls.{CallHistory, CallSummary, PreparedCall, UsageReport}

  @enforce_keys [:call, :prepared_call, :history, :usage]
  defstruct @enforce_keys

  @type availability(value) :: {:available, value} | {:unavailable, term()}

  @type t :: %__MODULE__{
          call: CallSummary.t(),
          prepared_call: PreparedCall.t(),
          history: CallHistory.t(),
          usage: availability(UsageReport.t())
        }
end
