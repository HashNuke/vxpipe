defmodule Vxpipe.CallEngine.Readiness.Report do
  @moduledoc false

  alias Vxpipe.CallEngine.Readiness.Resource

  @enforce_keys [:incarnation_id, :attempt_id, :request_id, :resource, :sequence, :status]
  defstruct @enforce_keys

  @type status :: :preparing | :ready | :failed
  @type t :: %__MODULE__{
          incarnation_id: String.t(),
          attempt_id: term(),
          request_id: reference(),
          resource: Resource.t(),
          sequence: non_neg_integer(),
          status: status()
        }
end
