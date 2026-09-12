defmodule Vxpipe.AgentRuntime.CompactionRequest do
  @moduledoc "Tool-less authorized input for one context-compaction attempt."

  alias Vxpipe.AgentRuntime.Message

  @enforce_keys [:messages, :maximum_summary_tokens, :correlation, :source_correlations]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          messages: [Message.t()],
          maximum_summary_tokens: pos_integer(),
          correlation: map(),
          source_correlations: [map()]
        }

  @spec new([Message.t()], pos_integer(), map(), [map()]) ::
          {:ok, t()} | {:error, :invalid_compaction_request}
  def new(messages, maximum_summary_tokens, correlation, source_correlations)
      when is_list(messages) and is_integer(maximum_summary_tokens) and
             maximum_summary_tokens > 0 and is_map(correlation) and
             is_list(source_correlations) do
    if messages != [] and Enum.all?(messages, &match?(%Message{}, &1)) and
         Enum.all?(source_correlations, &is_map/1) do
      {:ok,
       %__MODULE__{
         messages: messages,
         maximum_summary_tokens: maximum_summary_tokens,
         correlation: correlation,
         source_correlations: source_correlations
       }}
    else
      {:error, :invalid_compaction_request}
    end
  end

  def new(_messages, _maximum_summary_tokens, _correlation, _source_correlations),
    do: {:error, :invalid_compaction_request}
end
