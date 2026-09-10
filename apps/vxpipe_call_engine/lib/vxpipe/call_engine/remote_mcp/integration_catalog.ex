defmodule Vxpipe.CallEngine.RemoteMCP.IntegrationCatalog do
  @moduledoc """
  Resolves configured MCP integrations with tenant whole-record precedence.
  """

  alias Vxpipe.CallEngine.RemoteMCP.{Integration, ResolvedTool}
  alias Vxpipe.MCP.{ArgumentValidator, Catalog}

  @enforce_keys [:application, :tenants]
  defstruct @enforce_keys

  @maximum_identifier_bytes 128

  @opaque t :: %__MODULE__{
            application: %{String.t() => Integration.t()},
            tenants: %{String.t() => %{String.t() => Integration.t()}}
          }

  @type error ::
          :invalid_integration_catalog
          | :invalid_tool_descriptor
          | :integration_not_configured
          | :stale_integration
          | :tool_not_allowed
          | :unknown_tool
          | :unsupported_input_schema

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_integration_catalog}
  def new(options) when is_list(options) do
    with {:ok, options} <- Keyword.validate(options, [:application, :tenants]),
         application when is_map(application) <- Keyword.get(options, :application, %{}),
         tenants when is_map(tenants) <- Keyword.get(options, :tenants, %{}),
         :ok <- validate_integrations(application),
         :ok <- validate_tenants(tenants) do
      {:ok, %__MODULE__{application: application, tenants: tenants}}
    else
      _invalid -> {:error, :invalid_integration_catalog}
    end
  end

  @spec resolve(t(), String.t(), String.t(), String.t()) ::
          {:ok, ResolvedTool.t()} | {:error, error()}
  def resolve(%__MODULE__{} = catalog, tenant_id, integration_id, remote_name)
      when is_binary(tenant_id) and is_binary(integration_id) and is_binary(remote_name) do
    case tenant_integration(catalog, tenant_id, integration_id) do
      {:ok, integration} ->
        resolve_tool(integration, {:tenant, tenant_id}, remote_name)

      :error ->
        case Map.fetch(catalog.application, integration_id) do
          {:ok, integration} -> resolve_tool(integration, :application, remote_name)
          :error -> {:error, :integration_not_configured}
        end
    end
  end

  @spec checkout(t(), ResolvedTool.t()) ::
          {:ok, Integration.t()} | {:error, :stale_integration}
  def checkout(%__MODULE__{} = catalog, %ResolvedTool{} = resolved) do
    with {:ok, integration} <- scoped_integration(catalog, resolved),
         {:ok, current} <- resolve_tool(integration, resolved.scope, resolved.remote_name),
         true <- current == resolved do
      {:ok, integration}
    else
      _stale_or_invalid -> {:error, :stale_integration}
    end
  end

  defp scoped_integration(catalog, %ResolvedTool{
         scope: :application,
         integration_id: integration_id
       }) do
    Map.fetch(catalog.application, integration_id)
  end

  defp scoped_integration(catalog, %ResolvedTool{
         scope: {:tenant, tenant_id},
         integration_id: integration_id
       }) do
    tenant_integration(catalog, tenant_id, integration_id)
  end

  defp tenant_integration(catalog, tenant_id, integration_id) do
    with {:ok, integrations} <- Map.fetch(catalog.tenants, tenant_id),
         {:ok, integration} <- Map.fetch(integrations, integration_id) do
      {:ok, integration}
    else
      :error -> :error
    end
  end

  defp resolve_tool(integration, scope, remote_name) do
    with true <- MapSet.member?(integration.allowed_tools, remote_name),
         {:ok, descriptor} <- Catalog.fetch(integration.catalog, remote_name),
         {:ok, description} <- description(descriptor),
         input_schema when is_map(input_schema) <- Map.get(descriptor, "inputSchema"),
         :ok <- ArgumentValidator.validate_schema(input_schema) do
      {:ok,
       %ResolvedTool{
         scope: scope,
         integration_id: integration.integration_id,
         configuration_generation: integration.configuration_generation,
         credential_generation: integration.credential_generation,
         catalog_generation: integration.catalog_generation,
         remote_name: remote_name,
         description: description,
         input_schema: input_schema,
         invocation_deadline_ms: integration.invocation_deadline_ms,
         maximum_result_bytes: integration.maximum_result_bytes
       }}
    else
      false -> {:error, :tool_not_allowed}
      {:error, :unknown_tool} -> {:error, :unknown_tool}
      {:error, :unsupported_input_schema} -> {:error, :unsupported_input_schema}
      _invalid -> {:error, :invalid_tool_descriptor}
    end
  end

  defp description(descriptor) do
    case Map.get(descriptor, "description", "") do
      value when is_binary(value) -> {:ok, value}
      _invalid -> {:error, :invalid_tool_descriptor}
    end
  end

  defp validate_tenants(tenants) do
    Enum.reduce_while(tenants, :ok, fn
      {tenant_id, integrations}, :ok
      when is_binary(tenant_id) and byte_size(tenant_id) in 1..@maximum_identifier_bytes and
             is_map(integrations) ->
        continue(validate_integrations(integrations))

      _invalid, :ok ->
        {:halt, {:error, :invalid_integration_catalog}}
    end)
  end

  defp validate_integrations(integrations) do
    Enum.reduce_while(integrations, :ok, fn
      {integration_id, %Integration{integration_id: integration_id}}, :ok -> {:cont, :ok}
      _invalid, :ok -> {:halt, {:error, :invalid_integration_catalog}}
    end)
  end

  defp continue(:ok), do: {:cont, :ok}
  defp continue({:error, _reason} = error), do: {:halt, error}
end
