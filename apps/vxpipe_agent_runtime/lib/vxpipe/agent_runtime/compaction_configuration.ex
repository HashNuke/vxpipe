defmodule Vxpipe.AgentRuntime.CompactionConfiguration do
  @moduledoc false

  alias Vxpipe.AgentRuntime.{
    ConservativeInputTokenCounter,
    ContextBudget,
    ModelContextCompactor
  }

  @default_recent_entries 4
  @default_input_token_timeout_ms 1_000
  @default_compactor_timeout_ms 15_000

  @spec new(module(), term(), nil | false | keyword()) ::
          {:ok, nil | map()} | {:error, :invalid_compaction_configuration}
  def new(_model_provider, _model, nil), do: {:ok, nil}
  def new(_model_provider, _model, false), do: {:ok, nil}

  def new(model_provider, model, options) when is_atom(model_provider) and is_list(options) do
    with {:ok, options} <- validate_options(options),
         true <- Keyword.get(options, :enabled, false),
         {:ok, context_window_tokens} <-
           limit(options, :context_window_tokens, model_provider, model),
         {:ok, output_reserve_tokens} <-
           limit(options, :output_reserve_tokens, model_provider, model),
         {:ok, budget} <-
           ContextBudget.new(
             context_window_tokens: context_window_tokens,
             output_reserve_tokens: output_reserve_tokens
           ),
         {:ok, recent_entries} <-
           positive(Keyword.get(options, :recent_entries, @default_recent_entries)),
         {:ok, input_token_timeout_ms} <-
           positive(
             Keyword.get(
               options,
               :input_token_timeout_ms,
               @default_input_token_timeout_ms
             )
           ),
         {:ok, compactor_timeout_ms} <-
           positive(Keyword.get(options, :compactor_timeout_ms, @default_compactor_timeout_ms)),
         {:ok, input_token_counter} <-
           callback(
             Keyword.get(options, :input_token_counter, {ConservativeInputTokenCounter, nil}),
             :count
           ),
         {:ok, compactor} <-
           callback(
             Keyword.get(
               options,
               :compactor,
               {ModelContextCompactor, %{model_provider: model_provider, model: model}}
             ),
             :compact
           ) do
      {:ok,
       %{
         budget: budget,
         compactor: compactor,
         compactor_timeout_ms: compactor_timeout_ms,
         input_token_counter: input_token_counter,
         input_token_timeout_ms: input_token_timeout_ms,
         recent_entries: recent_entries
       }}
    else
      false -> {:ok, nil}
      _invalid -> {:error, :invalid_compaction_configuration}
    end
  end

  def new(_model_provider, _model, _options),
    do: {:error, :invalid_compaction_configuration}

  defp validate_options(options) do
    Keyword.validate(options, [
      :enabled,
      :context_window_tokens,
      :output_reserve_tokens,
      :recent_entries,
      :input_token_counter,
      :input_token_timeout_ms,
      :compactor,
      :compactor_timeout_ms
    ])
  end

  defp limit(options, key, model_provider, model) do
    case Keyword.get(options, key) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      nil -> provider_limit(model_provider, model, key)
      _invalid -> {:error, :invalid_limit}
    end
  end

  defp provider_limit(model_provider, model, :context_window_tokens) do
    provider_limit(model_provider, model, :context_window_tokens, :context_window_tokens)
  end

  defp provider_limit(model_provider, model, :output_reserve_tokens) do
    provider_limit(model_provider, model, :maximum_output_tokens, :output_reserve_tokens)
  end

  defp provider_limit(model_provider, model, callback, _key) do
    with true <- Code.ensure_loaded?(model_provider),
         true <- function_exported?(model_provider, callback, 1),
         value when is_integer(value) and value > 0 <- apply(model_provider, callback, [model]) do
      {:ok, value}
    else
      _missing -> {:error, :missing_provider_limit}
    end
  rescue
    _error -> {:error, :missing_provider_limit}
  end

  defp callback({module, _state} = callback, function) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, function, 2) do
      {:ok, callback}
    else
      {:error, :invalid_callback}
    end
  end

  defp callback(_callback, _function), do: {:error, :invalid_callback}

  defp positive(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive(_value), do: {:error, :invalid_limit}
end
