defmodule Vxpipe.CallEngine.Tool.Dispatcher.State do
  @moduledoc false

  alias Vxpipe.CallEngine.CallVariables.Binding
  alias Vxpipe.CallEngine.Tool.Executor

  @derive {Inspect, except: [:variable_binding, :tool_calls]}
  @enforce_keys [:executor, :maximum_result_bytes, :variable_binding, :tool_calls]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          executor: Executor.t(),
          maximum_result_bytes: pos_integer(),
          variable_binding: nil | Binding.t(),
          tool_calls: map()
        }
end
