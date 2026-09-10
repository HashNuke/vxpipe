defmodule Vxpipe.AgentRuntime.Conversation do
  @moduledoc "Committed model conversation owned by one runtime session."

  alias Vxpipe.AgentRuntime.Conversation.Entry
  alias Vxpipe.AgentRuntime.Message

  @derive {Inspect, only: [:size]}
  @enforce_keys [:entries, :messages, :size]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          entries: [Entry.t()],
          messages: [Message.t()],
          size: non_neg_integer()
        }

  @spec new(String.t()) :: t()
  def new(instructions) when is_binary(instructions) do
    entry = Entry.new([Message.system(instructions)], :permanent)
    rebuild([entry])
  end

  @spec append_exchange(t(), [Message.t()], map(), Entry.retention()) :: t()
  def append_exchange(%__MODULE__{} = conversation, messages, correlation, retention)
      when is_list(messages) and is_map(correlation) do
    entry = Entry.new(messages, retention, correlation)
    rebuild(conversation.entries ++ [entry])
  end

  @spec discard(t(), [map()]) :: t()
  def discard(%__MODULE__{} = conversation, correlations) when is_list(correlations) do
    discarded = MapSet.new(correlations)
    entries = Enum.reject(conversation.entries, &Entry.discardable_for?(&1, discarded))
    rebuild(entries)
  end

  defp rebuild(entries) do
    messages = Enum.flat_map(entries, & &1.messages)
    %__MODULE__{entries: entries, messages: messages, size: length(messages)}
  end
end
