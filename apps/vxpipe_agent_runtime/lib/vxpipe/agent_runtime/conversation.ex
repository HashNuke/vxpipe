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

  @spec new(String.t(), [Message.t()]) :: t()
  def new(instructions, initial_messages \\ [])

  def new(instructions, initial_messages)
      when is_binary(instructions) and is_list(initial_messages) do
    entries = [Entry.new([Message.system(instructions)], :permanent)]

    entries =
      if initial_messages == [] do
        entries
      else
        entries ++ [Entry.new(initial_messages, :permanent)]
      end

    rebuild(entries)
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

  @spec durable?(t(), map()) :: boolean()
  def durable?(%__MODULE__{} = conversation, correlation) when is_map(correlation) do
    Enum.any?(conversation.entries, &Entry.durable_for?(&1, correlation))
  end

  defp rebuild(entries) do
    messages = Enum.flat_map(entries, & &1.messages)
    %__MODULE__{entries: entries, messages: messages, size: length(messages)}
  end
end
