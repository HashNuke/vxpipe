defmodule Vxpipe.AgentRuntime.Conversation do
  @moduledoc "Committed model conversation owned by one runtime session."

  alias Vxpipe.AgentRuntime.Message

  @derive {Inspect, only: [:size]}
  @enforce_keys [:messages, :size]
  defstruct @enforce_keys

  @type t :: %__MODULE__{messages: [Message.t()], size: non_neg_integer()}

  @spec new(String.t()) :: t()
  def new(instructions) when is_binary(instructions) do
    %__MODULE__{messages: [Message.system(instructions)], size: 1}
  end

  @spec append(t(), [Message.t()]) :: t()
  def append(%__MODULE__{} = conversation, messages) when is_list(messages) do
    %__MODULE__{
      messages: conversation.messages ++ messages,
      size: conversation.size + length(messages)
    }
  end
end
