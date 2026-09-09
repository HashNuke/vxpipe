defmodule Vxpipe.CallEngine.Tool.Dispatcher.State do
  @moduledoc false

  alias Vxpipe.CallEngine.CallVariables.Binding
  alias Vxpipe.CallEngine.Tool.Executor

  @derive {Inspect,
           except: [
             :background_invocations,
             :background_supervisor,
             :completion_target,
             :variable_binding,
             :tool_calls
           ]}
  @enforce_keys [
    :background_invocations,
    :background_supervisor,
    :background_tool_timeout_ms,
    :completion_target,
    :executor,
    :maximum_background_tools,
    :maximum_result_bytes,
    :variable_binding,
    :tool_calls
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          background_invocations: map(),
          background_supervisor: nil | DynamicSupervisor.supervisor(),
          background_tool_timeout_ms: pos_integer(),
          completion_target: nil | GenServer.server(),
          executor: Executor.t(),
          maximum_background_tools: non_neg_integer(),
          maximum_result_bytes: pos_integer(),
          variable_binding: nil | Binding.t(),
          tool_calls: map()
        }
end
