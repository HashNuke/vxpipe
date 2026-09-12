defmodule Vxpipe.AgentRuntime.Provider.ReqLLM.Config do
  @moduledoc false

  alias LLMDB.Model

  @derive {Inspect, only: [:model, :streaming, :context_window_tokens, :maximum_output_tokens]}
  @enforce_keys [
    :api_key,
    :model,
    :generation_options,
    :streaming,
    :context_window_tokens,
    :maximum_output_tokens
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          api_key: String.t(),
          model: term(),
          generation_options: keyword(),
          streaming: boolean(),
          context_window_tokens: pos_integer() | nil,
          maximum_output_tokens: pos_integer() | nil
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_configuration}
  def new(options) when is_list(options) do
    with {:ok, options} <-
           Keyword.validate(options,
             api_key: nil,
             model: nil,
             generation_options: [],
             streaming: :auto
           ),
         api_key when is_binary(api_key) <- Keyword.fetch!(options, :api_key),
         true <- String.trim(api_key) != "",
         model_spec when is_binary(model_spec) <- Keyword.fetch!(options, :model),
         true <- String.trim(model_spec) != "",
         generation_options when is_list(generation_options) <-
           Keyword.fetch!(options, :generation_options),
         true <- Keyword.keyword?(generation_options),
         true <- protected_options_absent?(generation_options),
         streaming when streaming in [:auto, true, false] <- Keyword.fetch!(options, :streaming),
         {:ok, model} <- Elixir.ReqLLM.model(model_spec),
         {:ok, generation_options, processed_options} <-
           validate_generation_options(model, generation_options) do
      {:ok,
       %__MODULE__{
         api_key: api_key,
         model: model,
         generation_options: generation_options,
         streaming: resolve_streaming(streaming, model),
         context_window_tokens: context_window_tokens(model),
         maximum_output_tokens: maximum_output_tokens(processed_options)
       }}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def new(_options), do: {:error, :invalid_configuration}

  defp protected_options_absent?(options) do
    Enum.all?(
      [:api_key, :messages, :on_unsupported, :stream, :tools],
      &(not Keyword.has_key?(options, &1))
    )
  end

  defp validate_generation_options(model, generation_options) do
    with {:ok, provider} <- Elixir.ReqLLM.provider(model.provider),
         options <- Keyword.put(generation_options, :on_unsupported, :error),
         {:ok, processed} <-
           Elixir.ReqLLM.Provider.Options.process(provider, :chat, model, options) do
      {:ok, options, processed}
    end
  rescue
    _error -> {:error, :invalid_generation_options}
  end

  defp context_window_tokens(%Model{limits: %{context: value}})
       when is_integer(value) and value > 0,
       do: value

  defp context_window_tokens(_model), do: nil

  defp maximum_output_tokens(options) do
    Enum.find_value([:max_tokens, :max_completion_tokens, :max_output_tokens], fn key ->
      case Keyword.get(options, key) do
        value when is_integer(value) and value > 0 -> value
        _missing -> nil
      end
    end)
  end

  defp resolve_streaming(:auto, model), do: Elixir.ReqLLM.ModelHelpers.streaming_text?(model)
  defp resolve_streaming(streaming, _model), do: streaming
end
