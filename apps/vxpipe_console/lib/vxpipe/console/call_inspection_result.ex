defmodule Vxpipe.Console.CallInspectionResult do
  @moduledoc "Database records assembled for one versioned call-inspection response."

  alias Vxpipe.Calls.{CallDetailPage, DefinitionRevision, UsageReport}

  @enforce_keys [:persisted, :definition, :usage, :as_of]
  defstruct @enforce_keys

  @type availability(value) :: {:available, value} | {:unavailable, term()}

  @type t :: %__MODULE__{
          persisted: CallDetailPage.t(),
          definition: availability(DefinitionRevision.t()),
          usage: availability(UsageReport.t()),
          as_of: DateTime.t()
        }
end
