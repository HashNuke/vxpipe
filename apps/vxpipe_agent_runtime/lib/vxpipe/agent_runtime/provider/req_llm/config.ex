defmodule Vxpipe.AgentRuntime.Provider.ReqLLM.Config do
  @moduledoc false

  @derive {Inspect, only: [:model, :streaming]}
  @enforce_keys [:api_key, :model, :generation_options, :streaming]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          api_key: String.t(),
          model: term(),
          generation_options: keyword(),
          streaming: boolean()
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
         {:ok, model} <- Elixir.ReqLLM.model(model_spec) do
      {:ok,
       %__MODULE__{
         api_key: api_key,
         model: model,
         generation_options: generation_options,
         streaming: resolve_streaming(streaming, model)
       }}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  def new(_options), do: {:error, :invalid_configuration}

  defp protected_options_absent?(options) do
    Enum.all?([:api_key, :messages, :stream, :tools], &(not Keyword.has_key?(options, &1)))
  end

  defp resolve_streaming(:auto, model), do: Elixir.ReqLLM.ModelHelpers.streaming_text?(model)
  defp resolve_streaming(streaming, _model), do: streaming
end
