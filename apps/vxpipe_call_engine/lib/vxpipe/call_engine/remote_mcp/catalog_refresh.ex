defmodule Vxpipe.CallEngine.RemoteMCP.CatalogRefresh do
  @moduledoc """
  Loads and atomically publishes one complete configured MCP catalog snapshot.

  Scheduling and configuration retrieval belong to the caller. Failed refreshes leave the
  previously published snapshot unchanged.
  """

  alias Vxpipe.CallEngine.RemoteMCP.{
    CatalogLoader,
    CatalogStore,
    ConfiguredIntegration,
    Integration,
    IntegrationCatalog
  }

  alias Vxpipe.MCP.ConnectionKey

  @default_maximum_concurrency 4
  @maximum_concurrency 32

  @type error ::
          :catalog_store_unavailable
          | :duplicate_integration
          | :invalid_refresh_configuration
          | {:integration_load_failed, ConnectionKey.t(), term()}

  @spec run([ConfiguredIntegration.t()], keyword()) ::
          {:ok, IntegrationCatalog.t()} | {:error, error()}
  def run(configured, options \\ [])

  def run(configured, options) when is_list(configured) and is_list(options) do
    with {:ok, options} <- validate_options(options),
         :ok <- validate_configured(configured),
         :ok <- unique_integrations(configured),
         {:ok, loaded} <- load_all(configured, options),
         {:ok, snapshot} <- build_snapshot(loaded),
         :ok <- publish(snapshot, Keyword.fetch!(options, :catalog_store)) do
      {:ok, snapshot}
    end
  end

  def run(_configured, _options), do: {:error, :invalid_refresh_configuration}

  defp validate_options(options) do
    with {:ok, options} <-
           Keyword.validate(options, [
             :catalog_store,
             :connection_provider,
             :maximum_concurrency,
             :protocol
           ]),
         maximum_concurrency when maximum_concurrency in 1..@maximum_concurrency <-
           Keyword.get(options, :maximum_concurrency, @default_maximum_concurrency) do
      {:ok,
       options
       |> Keyword.put_new(:catalog_store, CatalogStore)
       |> Keyword.put(:maximum_concurrency, maximum_concurrency)}
    else
      _invalid -> {:error, :invalid_refresh_configuration}
    end
  end

  defp validate_configured(configured) do
    if Enum.all?(configured, &match?(%ConfiguredIntegration{}, &1)),
      do: :ok,
      else: {:error, :invalid_refresh_configuration}
  end

  defp unique_integrations(configured) do
    identities = Enum.map(configured, &integration_identity/1)

    if Enum.uniq(identities) == identities,
      do: :ok,
      else: {:error, :duplicate_integration}
  end

  defp integration_identity(configured) do
    key = configured.connection_key
    {key.scope, key.integration_id}
  end

  defp load_all(configured, options) do
    loader_options = Keyword.take(options, [:connection_provider, :protocol])

    configured
    |> Task.async_stream(&load(&1, loader_options),
      max_concurrency: Keyword.fetch!(options, :maximum_concurrency),
      ordered: true,
      timeout: :infinity
    )
    |> Enum.reduce_while({:ok, []}, &collect_loaded/2)
    |> case do
      {:ok, loaded} -> {:ok, Enum.reverse(loaded)}
      {:error, _reason} = error -> error
    end
  end

  defp load(%ConfiguredIntegration{} = configured, options) do
    result = CatalogLoader.load(configured, options)
    {configured.connection_key, result}
  rescue
    _exception -> {configured.connection_key, {:error, :load_failed}}
  catch
    :exit, _reason -> {configured.connection_key, {:error, :load_failed}}
  end

  defp collect_loaded(
         {:ok, {%ConnectionKey{} = key, {:ok, %Integration{} = integration}}},
         {:ok, loaded}
       ) do
    {:cont, {:ok, [{key, integration} | loaded]}}
  end

  defp collect_loaded(
         {:ok, {%ConnectionKey{} = key, {:error, reason}}},
         {:ok, _loaded}
       ) do
    {:halt, {:error, {:integration_load_failed, key, reason}}}
  end

  defp collect_loaded(_invalid, {:ok, _loaded}) do
    {:halt, {:error, :invalid_refresh_configuration}}
  end

  defp build_snapshot(loaded) do
    {application, tenants} =
      Enum.reduce(loaded, {%{}, %{}}, fn
        {%ConnectionKey{scope: :application, integration_id: id}, integration},
        {application, tenants} ->
          {Map.put(application, id, integration), tenants}

        {%ConnectionKey{scope: {:tenant, tenant_id}, integration_id: id}, integration},
        {application, tenants} ->
          tenant_integrations = tenants |> Map.get(tenant_id, %{}) |> Map.put(id, integration)
          {application, Map.put(tenants, tenant_id, tenant_integrations)}
      end)

    IntegrationCatalog.new(application: application, tenants: tenants)
  end

  defp publish(snapshot, catalog_store) do
    CatalogStore.publish(catalog_store, snapshot)
  catch
    :exit, _reason -> {:error, :catalog_store_unavailable}
  end
end
