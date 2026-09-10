defmodule Vxpipe.AgentRuntime.ModelRequest do
  @moduledoc "One normalized provider generation request."

  alias Vxpipe.AgentRuntime.{Message, ModelTool, PendingInvocation}

  @derive {Inspect, only: [:correlation]}
  @enforce_keys [:messages, :tools, :pending_invocations, :correlation]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          messages: [Message.t()],
          tools: [ModelTool.t()],
          pending_invocations: [PendingInvocation.t()],
          correlation: map()
        }

  @spec new([Message.t()], [ModelTool.t()], [PendingInvocation.t()], map()) :: t()
  def new(messages, tools, pending_invocations, correlation)
      when is_list(messages) and is_list(tools) and is_list(pending_invocations) and
             is_map(correlation) do
    %__MODULE__{
      messages: messages,
      tools: tools,
      pending_invocations: pending_invocations,
      correlation: correlation
    }
  end
end
