defmodule Vxpipe.CallEngine.RemoteMCP.CatalogLoader do
  @moduledoc """
  Loads one complete discovered catalog for validated scoped integration configuration.
  """

  alias Vxpipe.CallEngine.RemoteMCP.{ConfiguredIntegration, Integration}
  alias Vxpipe.MCP.{Connection, Connections, Discovery, ExMCPClient}

  @type error ::
          :connection_failed
          | :credential_revoked
          | :invalid_configuration
          | :invalid_discovered_catalog
          | Discovery.error()

  @spec load(ConfiguredIntegration.t(), keyword()) ::
          {:ok, Integration.t()} | {:error, error()}
  def load(configured, options \\ [])

  def load(%ConfiguredIntegration{} = configured, options) when is_list(options) do
    with {:ok, options} <- validate_options(options),
         {:ok, connection_provider} <-
           module_with_function(Keyword.get(options, :connection_provider, Connections), :open, 2),
         {:ok, protocol} <-
           module_with_function(Keyword.get(options, :protocol, ExMCPClient), :list_tools, 3),
         {:ok, connection} <- open(configured, connection_provider),
         {:ok, catalog} <- discover(configured, connection, protocol),
         {:ok, integration} <- build_integration(configured, catalog) do
      {:ok, integration}
    else
      {:error, :credential_revoked} = error ->
        error

      {:error, reason} when reason in [:invalid_configuration, :invalid_discovered_catalog] ->
        {:error, reason}

      {:error, reason} when reason in [:connection_failed, :invalid_connection] ->
        {:error, :connection_failed}

      {:error, reason} ->
        {:error, reason}

      _invalid ->
        {:error, :invalid_configuration}
    end
  end

  def load(%ConfiguredIntegration{}, _options), do: {:error, :invalid_configuration}

  defp validate_options(options) do
    case Keyword.validate(options, [:connection_provider, :protocol]) do
      {:ok, options} -> {:ok, options}
      {:error, _reason} -> {:error, :invalid_configuration}
    end
  end

  defp module_with_function(module, function, arity) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, function, arity) do
      {:ok, module}
    else
      {:error, :invalid_configuration}
    end
  end

  defp module_with_function(_module, _function, _arity), do: {:error, :invalid_configuration}

  defp open(configured, connection_provider) do
    config = enforce_response_limits(configured)

    case connection_provider.open(configured.connection_key, config) do
      {:ok, %Connection{} = connection} ->
        if Connection.key(connection) == configured.connection_key do
          {:ok, connection}
        else
          {:error, :invalid_connection}
        end

      {:error, :credential_revoked} = error ->
        error

      _failure ->
        {:error, :connection_failed}
    end
  end

  defp enforce_response_limits(configured) do
    limits =
      configured.client_config
      |> Keyword.get(:limits, [])
      |> Keyword.merge(
        max_response_bytes: configured.maximum_result_bytes,
        max_stream_buffer_bytes: configured.maximum_result_bytes
      )

    Keyword.put(configured.client_config, :limits, limits)
  end

  defp discover(configured, connection, protocol) do
    Discovery.discover(Connection.client(connection),
      protocol: protocol,
      deadline_ms: configured.discovery_deadline_ms,
      max_pages: configured.maximum_discovery_pages,
      max_decoded_bytes: configured.maximum_discovery_bytes
    )
  end

  defp build_integration(configured, catalog) do
    key = configured.connection_key

    case Integration.new(
           integration_id: key.integration_id,
           configuration_generation: configured.configuration_generation,
           credential_generation: key.credential_generation,
           catalog_generation: configured.catalog_generation,
           catalog: catalog,
           allowed_tools: configured.allowed_tools,
           client_config: configured.client_config,
           invocation_deadline_ms: configured.invocation_deadline_ms,
           maximum_result_bytes: configured.maximum_result_bytes
         ) do
      {:ok, integration} -> {:ok, integration}
      {:error, :invalid_integration} -> {:error, :invalid_discovered_catalog}
    end
  end
end
