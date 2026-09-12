defmodule Vxpipe.AgentRuntime.Conversation.Entry do
  @moduledoc false

  alias Vxpipe.AgentRuntime.Message

  @derive {Inspect, only: [:retention]}
  @enforce_keys [:messages, :retention]
  defstruct @enforce_keys ++ [correlation: nil, durable_correlations: [], source_correlations: []]

  @type retention :: :permanent | :durable | :discardable
  @type t :: %__MODULE__{
          messages: [Message.t()],
          retention: retention(),
          correlation: map() | nil,
          durable_correlations: [map()],
          source_correlations: [map()]
        }

  @spec new([Message.t()], retention(), map() | nil) :: t()
  def new(messages, retention, correlation \\ nil)

  def new(messages, retention, correlation)
      when is_list(messages) and retention in [:permanent, :durable, :discardable] and
             (is_map(correlation) or is_nil(correlation)) do
    %__MODULE__{messages: messages, retention: retention, correlation: correlation}
  end

  @doc false
  @spec summary([Message.t()], [map()], [map()]) :: t()
  def summary(messages, source_correlations, durable_correlations)
      when is_list(messages) and is_list(source_correlations) and
             is_list(durable_correlations) do
    %__MODULE__{
      messages: messages,
      retention: :durable,
      durable_correlations: durable_correlations,
      source_correlations: source_correlations
    }
  end

  @spec discardable_for?(t(), MapSet.t()) :: boolean()
  def discardable_for?(%__MODULE__{} = entry, correlations) do
    entry.retention == :discardable and MapSet.member?(correlations, entry.correlation)
  end

  @spec durable_for?(t(), map()) :: boolean()
  def durable_for?(%__MODULE__{} = entry, correlation) when is_map(correlation) do
    entry.retention == :durable and
      (entry.correlation == correlation or correlation in entry.durable_correlations)
  end

  @doc false
  @spec durable_correlations(t()) :: [map()]
  def durable_correlations(%__MODULE__{retention: :durable} = entry) do
    case entry.correlation do
      correlation when is_map(correlation) -> [correlation | entry.durable_correlations]
      nil -> entry.durable_correlations
    end
  end

  def durable_correlations(%__MODULE__{}), do: []

  @doc false
  @spec source_correlations(t()) :: [map()]
  def source_correlations(%__MODULE__{} = entry) do
    case entry.correlation do
      correlation when is_map(correlation) -> [correlation | entry.source_correlations]
      nil -> entry.source_correlations
    end
  end
end
