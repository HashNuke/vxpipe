defmodule Vxpipe.AgentRuntime.Conversation.Entry do
  @moduledoc false

  alias Vxpipe.AgentRuntime.Message

  @derive {Inspect, only: [:retention]}
  @enforce_keys [:messages, :retention]
  defstruct @enforce_keys ++ [correlation: nil]

  @type retention :: :permanent | :durable | :discardable
  @type t :: %__MODULE__{
          messages: [Message.t()],
          retention: retention(),
          correlation: map() | nil
        }

  @spec new([Message.t()], retention(), map() | nil) :: t()
  def new(messages, retention, correlation \\ nil)

  def new(messages, retention, correlation)
      when is_list(messages) and retention in [:permanent, :durable, :discardable] and
             (is_map(correlation) or is_nil(correlation)) do
    %__MODULE__{messages: messages, retention: retention, correlation: correlation}
  end

  @spec discardable_for?(t(), MapSet.t()) :: boolean()
  def discardable_for?(%__MODULE__{} = entry, correlations) do
    entry.retention == :discardable and MapSet.member?(correlations, entry.correlation)
  end

  @spec durable_for?(t(), map()) :: boolean()
  def durable_for?(%__MODULE__{} = entry, correlation) when is_map(correlation) do
    entry.retention == :durable and entry.correlation == correlation
  end
end
