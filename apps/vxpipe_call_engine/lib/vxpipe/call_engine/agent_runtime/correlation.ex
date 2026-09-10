defmodule Vxpipe.CallEngine.AgentRuntime.Correlation do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.Context

  @derive {Inspect, only: [:command_id, :correlation_id]}
  @enforce_keys [:command_id, :correlation_id, :invocation_registry, :tool_context]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          command_id: String.t(),
          correlation_id: String.t(),
          invocation_registry: GenServer.server(),
          tool_context: Context.t()
        }

  @spec new(GenServer.server(), Context.t()) :: t()
  def new(invocation_registry, %Context{} = tool_context)
      when not is_nil(invocation_registry) do
    %__MODULE__{
      command_id: tool_context.command_id,
      correlation_id: tool_context.correlation_id,
      invocation_registry: invocation_registry,
      tool_context: tool_context
    }
  end

  @spec registry?(t(), GenServer.server()) :: boolean()
  def registry?(%__MODULE__{} = correlation, registry) do
    correlation.invocation_registry == registry
  end
end
