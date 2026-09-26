defmodule Vxpipe.CallEngine.PlanStartup.AgentModel do
  @moduledoc false

  alias Vxpipe.AgentRuntime.{ProviderSelection, Provider.ReqLLM}
  alias Vxpipe.CallEngine.{CredentialSource, ProviderCredential}
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection

  @derive {Inspect, only: [:model, :provider]}
  @enforce_keys [:model, :provider, :configuration]
  defstruct @enforce_keys

  @type t :: %__MODULE__{model: String.t(), provider: module(), configuration: term()}

  def resolve(%CapabilitySelection{provider: provider} = selection, tenant_id, options)
      when provider in ["google", "zenmux", "openai"] do
    with {:ok, %ProviderCredential{auth_kind: "api_key", payload: %{"api_key" => api_key}}} <-
           CredentialSource.resolve(tenant_id, selection, options),
         {:ok, provider_options} <-
           ProviderSelection.translate(
             selection.provider,
             selection.model,
             selection.options,
             selection.provider_options
           ),
         {:ok, configuration} <-
           initialize(ReqLLM, Keyword.put(provider_options, :api_key, api_key), options) do
      {:ok,
       %__MODULE__{
         model: Keyword.fetch!(provider_options, :model),
         provider: ReqLLM,
         configuration: configuration
       }}
    else
      _unavailable -> {:error, :unsupported_provider_options}
    end
  end

  def resolve(%CapabilitySelection{provider: "fixture", model: model}, _tenant_id, options) do
    settings = Keyword.fetch!(options, :agent_runtime)

    with {adapter, fixture_options}
         when is_atom(adapter) and adapter != ReqLLM and is_list(fixture_options) <-
           Keyword.get(settings, :fixture),
         false <- Vxpipe.CallEngine.CallSpecValidation.private_data?(fixture_options),
         {:ok, configuration} <-
           initialize(adapter, Keyword.put(fixture_options, :model, model), options) do
      {:ok, %__MODULE__{model: model, provider: adapter, configuration: configuration}}
    else
      _unavailable -> {:error, :unsupported_provider_options}
    end
  end

  def resolve(_selection, _tenant_id, _options), do: {:error, :unsupported_provider_options}

  defp initialize(provider, options, runtime_options) do
    lifecycle =
      runtime_options |> Keyword.fetch!(:agent_runtime) |> Keyword.get(:startup_lifecycle)

    _ = Vxpipe.CallEngine.CallLifecycle.startup_progress(lifecycle, self(), [:model_inference])
    result = provider.new(options)

    if match?({:ok, _}, result),
      do: Vxpipe.CallEngine.CallLifecycle.startup_progress(lifecycle, self(), [])

    result
  end
end
