defmodule Vxpipe.AgentRuntime.ContextBudget do
  @moduledoc "Token thresholds for deciding when model context must be compacted."

  @enforce_keys [
    :context_window_tokens,
    :output_reserve_tokens,
    :usable_input_tokens,
    :trigger_input_tokens,
    :target_input_tokens
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          context_window_tokens: pos_integer(),
          output_reserve_tokens: pos_integer(),
          usable_input_tokens: pos_integer(),
          trigger_input_tokens: pos_integer(),
          target_input_tokens: non_neg_integer()
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_context_budget}
  def new(options) when is_list(options) do
    with {:ok, options} <-
           Keyword.validate(options, [:context_window_tokens, :output_reserve_tokens]),
         context_window_tokens
         when is_integer(context_window_tokens) and context_window_tokens > 0 <-
           Keyword.get(options, :context_window_tokens),
         output_reserve_tokens
         when is_integer(output_reserve_tokens) and output_reserve_tokens > 0 <-
           Keyword.get(options, :output_reserve_tokens),
         usable_input_tokens when usable_input_tokens > 1 <-
           context_window_tokens - output_reserve_tokens do
      {:ok,
       %__MODULE__{
         context_window_tokens: context_window_tokens,
         output_reserve_tokens: output_reserve_tokens,
         usable_input_tokens: usable_input_tokens,
         trigger_input_tokens: ceil_percent(usable_input_tokens, 75),
         target_input_tokens: div(usable_input_tokens - 1, 2)
       }}
    else
      _invalid -> {:error, :invalid_context_budget}
    end
  end

  def new(_options), do: {:error, :invalid_context_budget}

  @spec assess(t(), non_neg_integer()) ::
          {:ok, :within_budget | {:compact, non_neg_integer()}}
          | {:error, :invalid_input_token_count}
  def assess(%__MODULE__{} = budget, input_tokens)
      when is_integer(input_tokens) and input_tokens >= 0 do
    if input_tokens >= budget.trigger_input_tokens do
      {:ok, {:compact, budget.target_input_tokens}}
    else
      {:ok, :within_budget}
    end
  end

  def assess(%__MODULE__{}, _input_tokens), do: {:error, :invalid_input_token_count}

  defp ceil_percent(value, percent), do: div(value * percent + 99, 100)
end
