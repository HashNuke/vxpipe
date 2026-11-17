defmodule Vxpipe.AgentRuntime.ModelRequest do
  @moduledoc """
  One normalized provider generation request and its host control context.

  pending_invocations is host-only bookkeeping for compaction and execution safety.
  It is excluded from model-visible messages, provider wire payloads and token
  estimates. Native historical tool calls and responses remain in messages.
  """

  alias Vxpipe.AgentRuntime.{Message, ModelTool, PendingInvocation}

  @derive {Inspect, only: [:correlation]}
  @enforce_keys [:messages, :tools, :pending_invocations, :model_context, :correlation]
  defstruct @enforce_keys ++ [maximum_output_tokens: nil, reply_protocol: :legacy]

  @type t :: %__MODULE__{
          messages: [Message.t()],
          tools: [ModelTool.t()],
          pending_invocations: [PendingInvocation.t()],
          model_context: map(),
          correlation: map(),
          maximum_output_tokens: pos_integer() | nil,
          reply_protocol: :legacy | :mode_message_v1
        }

  @spec new([Message.t()], [ModelTool.t()], [PendingInvocation.t()], map()) :: t()
  def new(messages, tools, pending_invocations, correlation)
      when is_list(messages) and is_list(tools) and is_list(pending_invocations) and
             is_map(correlation) do
    new(messages, tools, pending_invocations, %{}, correlation)
  end

  @spec new([Message.t()], [ModelTool.t()], [PendingInvocation.t()], map(), map()) :: t()
  def new(messages, tools, pending_invocations, model_context, correlation)
      when is_list(messages) and is_list(tools) and is_list(pending_invocations) and
             is_map(model_context) and is_map(correlation) do
    %__MODULE__{
      messages: messages,
      tools: tools,
      pending_invocations: pending_invocations,
      model_context: model_context,
      correlation: correlation
    }
  end

  @doc false
  @spec with_messages(t(), [Message.t()]) :: t()
  def with_messages(%__MODULE__{} = request, messages) when is_list(messages) do
    %{request | messages: messages}
  end

  @doc false
  @spec with_maximum_output_tokens(t(), pos_integer()) :: t()
  def with_maximum_output_tokens(%__MODULE__{} = request, maximum_output_tokens)
      when is_integer(maximum_output_tokens) and maximum_output_tokens > 0 do
    %{request | maximum_output_tokens: maximum_output_tokens}
  end
end
