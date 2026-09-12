defmodule Vxpipe.CallEngine.PlanStartup.AgentModelProfile do
  @moduledoc false

  alias Vxpipe.CallEngine.CallDefinition.CapabilitySelection

  @derive {Inspect, only: [:model, :provider]}
  @enforce_keys [:model, :provider, :configuration]
  @application_owned_generation_options [
    :api_key,
    :messages,
    :on_unsupported,
    :output_repair,
    :req_http_options,
    :stream,
    :tools
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          model: String.t(),
          provider: module(),
          configuration: term()
        }

  @spec resolve(CapabilitySelection.t(), keyword()) ::
          {:ok, t()} | {:error, :unsupported_provider_options}
  def resolve(
        %CapabilitySelection{provider: :req_llm, options: profile_options},
        settings
      )
      when is_map(profile_options) and is_list(settings) do
    with {:ok, profile_options} <- normalize_profile_options(profile_options),
         model when is_binary(model) <- Map.get(profile_options, :model),
         true <- String.trim(model) != "",
         generation_options when is_list(generation_options) <-
           Map.get(profile_options, :generation_options, []),
         true <- Keyword.keyword?(generation_options),
         true <- data_only?(generation_options),
         true <- application_owned_options_absent?(generation_options),
         provider when is_atom(provider) <- Keyword.get(settings, :model_provider),
         true <- Code.ensure_loaded?(provider),
         true <- function_exported?(provider, :new, 1),
         base_options when is_list(base_options) <-
           Keyword.get(settings, :model_provider_options),
         true <- Keyword.keyword?(base_options),
         base_generation_options when is_list(base_generation_options) <-
           Keyword.get(base_options, :generation_options, []),
         true <- Keyword.keyword?(base_generation_options),
         provider_options <-
           build_provider_options(
             base_options,
             model,
             base_generation_options,
             generation_options,
             Map.has_key?(profile_options, :generation_options)
           ),
         {:ok, configuration} <- provider.new(provider_options) do
      {:ok,
       %__MODULE__{
         model: model,
         provider: provider,
         configuration: configuration
       }}
    else
      _invalid -> {:error, :unsupported_provider_options}
    end
  rescue
    _exception -> {:error, :unsupported_provider_options}
  end

  def resolve(_selection, _settings), do: {:error, :unsupported_provider_options}

  defp normalize_profile_options(options) do
    Enum.reduce_while(options, {:ok, %{}}, fn {key, value}, {:ok, normalized} ->
      case normalize_key(key) do
        {:ok, key} ->
          if Map.has_key?(normalized, key) do
            {:halt, {:error, :duplicate_provider_option}}
          else
            {:cont, {:ok, Map.put(normalized, key, value)}}
          end

        :error ->
          {:halt, {:error, :unsupported_provider_option}}
      end
    end)
  end

  defp normalize_key(key) when key in [:model, "model"], do: {:ok, :model}

  defp normalize_key(key) when key in [:generation_options, "generation_options"],
    do: {:ok, :generation_options}

  defp normalize_key(_key), do: :error

  defp data_only?(value)
       when is_atom(value) or is_binary(value) or is_boolean(value) or is_number(value),
       do: true

  defp data_only?(value) when is_list(value) do
    if Keyword.keyword?(value) do
      Enum.all?(value, fn {key, nested} -> is_atom(key) and data_only?(nested) end)
    else
      Enum.all?(value, &data_only?/1)
    end
  end

  defp data_only?(%_struct{}), do: false

  defp data_only?(value) when is_map(value) do
    Enum.all?(value, fn {key, nested} ->
      (is_atom(key) or is_binary(key)) and data_only?(nested)
    end)
  end

  defp data_only?(_value), do: false

  defp application_owned_options_absent?(options) do
    Enum.all?(@application_owned_generation_options, &(not Keyword.has_key?(options, &1)))
  end

  defp build_provider_options(
         base_options,
         model,
         base_generation_options,
         generation_options,
         profile_generation_options?
       ) do
    merged_generation_options = Keyword.merge(base_generation_options, generation_options)
    provider_options = Keyword.put(base_options, :model, model)

    if Keyword.has_key?(base_options, :generation_options) or profile_generation_options? do
      Keyword.put(provider_options, :generation_options, merged_generation_options)
    else
      provider_options
    end
  end
end
