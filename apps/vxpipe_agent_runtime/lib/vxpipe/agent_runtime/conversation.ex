defmodule Vxpipe.AgentRuntime.Conversation do
  @moduledoc "Committed model conversation owned by one runtime session."

  alias Vxpipe.AgentRuntime.Conversation.Entry
  alias Vxpipe.AgentRuntime.Message

  @derive {Inspect, only: [:size, :version]}
  @enforce_keys [:entries, :messages, :size]
  defstruct @enforce_keys ++ [version: 0]

  @type t :: %__MODULE__{
          entries: [Entry.t()],
          messages: [Message.t()],
          size: non_neg_integer(),
          version: non_neg_integer()
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

  @doc "Returns only committed dialogue for the host to permission-filter for a new candidate."
  def recent_dialogue(%__MODULE__{} = conversation, excluding) do
    newest =
      conversation.entries
      |> Enum.reverse()
      |> Stream.reject(&(&1.correlation == excluding and not is_nil(excluding)))
      |> Stream.flat_map(fn entry ->
        entry.messages
        |> Enum.reverse()
        |> Stream.filter(fn
          %Message{role: :user, origin: :caller} -> true
          %Message{role: :assistant, origin: nil, tool_calls: []} -> true
          _private -> false
        end)
        |> Stream.map(&{&1.role, &1.content, entry.correlation})
      end)
      |> Enum.take(5)

    compacted? = Enum.any?(conversation.entries, &(&1.source_correlations != []))
    {newest |> Enum.take(4) |> Enum.reverse(), compacted? or length(newest) > 4}
  end

  @spec append_exchange(t(), [Message.t()], map(), Entry.retention()) :: t()
  def append_exchange(%__MODULE__{} = conversation, messages, correlation, retention)
      when is_list(messages) and is_map(correlation) do
    entry = Entry.new(messages, retention, correlation)
    rebuild(conversation.entries ++ [entry], conversation.version + 1)
  end

  @doc "Places a playback receipt after the last exchange belonging to its source request."
  def settle_delivery(conversation, nil, correlation) do
    entries =
      Enum.reject(conversation.entries, &(&1.messages == [] and &1.correlation == correlation))

    if entries == conversation.entries,
      do: conversation,
      else: from_entries(entries, conversation.version + 1)
  end

  def settle_delivery(%__MODULE__{} = conversation, message, correlation) do
    {later, earlier} =
      conversation.entries
      |> Enum.reverse()
      |> Enum.split_while(&(correlation not in Entry.source_correlations(&1)))

    case earlier do
      [] ->
        append_exchange(conversation, [message], correlation, :durable)

      _ ->
        receipt = Entry.new([message], :durable, correlation)

        # A fixed greeting reserves a position without adding a model message.
        earlier =
          case earlier do
            [%Entry{messages: [], correlation: ^correlation} | prefix] -> prefix
            entries -> entries
          end

        from_entries(
          Enum.reverse(earlier, [receipt | Enum.reverse(later)]),
          conversation.version + 1
        )
    end
  end

  @spec discard(t(), [map()]) :: t()
  def discard(%__MODULE__{} = conversation, correlations) when is_list(correlations) do
    discarded = MapSet.new(correlations)
    entries = Enum.reject(conversation.entries, &Entry.discardable_for?(&1, discarded))

    if length(entries) == length(conversation.entries) do
      conversation
    else
      rebuild(entries, conversation.version + 1)
    end
  end

  @spec durable?(t(), map()) :: boolean()
  def durable?(%__MODULE__{} = conversation, correlation) when is_map(correlation) do
    Enum.any?(conversation.entries, &Entry.durable_for?(&1, correlation))
  end

  @doc false
  @spec from_entries([Entry.t()]) :: t()
  def from_entries(entries) when is_list(entries), do: rebuild(entries, 0)

  @doc false
  @spec from_entries([Entry.t()], non_neg_integer()) :: t()
  def from_entries(entries, version)
      when is_list(entries) and is_integer(version) and version >= 0,
      do: rebuild(entries, version)

  defp rebuild(entries), do: rebuild(entries, 0)

  defp rebuild(entries, version) do
    messages = Enum.flat_map(entries, & &1.messages)
    %__MODULE__{entries: entries, messages: messages, size: length(messages), version: version}
  end
end
