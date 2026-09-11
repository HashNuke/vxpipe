defmodule Vxpipe.Artifacts.Metadata.Publisher.State do
  @moduledoc false

  alias Vxpipe.Artifacts.Metadata.Configuration
  alias Vxpipe.Artifacts.Result

  @enforce_keys [:result, :configuration, :observer]
  defstruct @enforce_keys ++ [attempt: 0, task: nil, timeout_timer: nil]

  @type t :: %__MODULE__{
          result: Result.t(),
          configuration: Configuration.t(),
          observer: nil | pid(),
          attempt: non_neg_integer(),
          task: nil | Task.t(),
          timeout_timer: nil | reference()
        }
end
