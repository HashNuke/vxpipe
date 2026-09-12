defmodule Vxpipe.Calls.PublicationWorker.State do
  @moduledoc false

  alias Vxpipe.Calls.PublicationJob

  @enforce_keys [:job]
  defstruct @enforce_keys ++ [attempt: 0, task: nil, timeout_timer: nil]

  @type t :: %__MODULE__{
          job: PublicationJob.t(),
          attempt: non_neg_integer(),
          task: nil | Task.t(),
          timeout_timer: nil | reference()
        }
end
