defmodule Vxpipe.CallEngine.RemoteMCPIdentityProbe do
  @moduledoc false

  alias Vxpipe.CallEngine.RemoteMCP.{
    CatalogLoader,
    ConfiguredIntegration,
    IntegrationCatalog,
    IntegrationOwner
  }

  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding

  def measure(churn_count, offset \\ 0)

  def measure(churn_count, offset)
      when is_integer(churn_count) and churn_count > 0 and is_integer(offset) and offset >= 0 do
    {:ok, _applications} = Application.ensure_all_started(:vxpipe_mcp)
    {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)

    try do
      warmup_range = (offset + 1)..(offset + churn_count)
      measured_range = (offset + churn_count + 1)..(offset + 2 * churn_count)

      Enum.each(warmup_range, &churn_once!(supervisor, &1))
      _ = :code.all_loaded()
      atoms_before = :erlang.system_info(:atom_count)
      modules_before = loaded_modules()

      Enum.each(measured_range, &churn_once!(supervisor, &1))
      :erlang.garbage_collect()

      %{
        atom_growth: :erlang.system_info(:atom_count) - atoms_before,
        module_growth: MapSet.size(MapSet.difference(loaded_modules(), modules_before)),
        atomized_values: atomized_external_values(measured_range)
      }
    after
      Supervisor.stop(supervisor)
    end
  end

  defp churn_once!(supervisor, index) do
    identity = identity(index)
    client = start_client!(supervisor, identity)
    configured = configured!(identity, client)
    integration = load!(configured)
    catalog = catalog!(identity, integration)
    resolved = resolve!(catalog, identity)

    binding = %ToolBinding{
      name: identity.local_name,
      type: :mcp,
      action: nil,
      remote: resolved
    }

    owner = start_owner!(supervisor, identity, catalog, binding)
    arguments = %{identity.field_name => "value-#{index}"}

    {:ok, %{"content" => [%{"text" => result, "type" => "text"}]}} =
      IntegrationOwner.execute(owner, identity.local_name, arguments)

    true = result == "result-#{index}"

    inspected =
      inspect([configured, integration, catalog, resolved, binding, :sys.get_state(owner)])

    false = inspected =~ identity.endpoint

    :ok = DynamicSupervisor.terminate_child(supervisor, owner)
    :ok = DynamicSupervisor.terminate_child(supervisor, client)
  end

  defp identity(index) do
    %{
      catalog_generation: "catalog-#{index}",
      configuration_generation: "configuration-#{index}",
      credential_generation: "credential-#{index}",
      endpoint: "https://mcp-#{index}.example.test/mcp",
      field_name: "field-#{index}",
      integration_id: "integration-#{index}",
      local_name: "local-tool-#{index}",
      remote_name: "remote-tool-#{index}",
      tenant_id: "tenant-#{index}"
    }
  end

  defp start_client!(supervisor, identity) do
    response = {:ok, %{"content" => [%{"type" => "text", "text" => result(identity)}]}}

    {:ok, client} =
      DynamicSupervisor.start_child(
        supervisor,
        Supervisor.child_spec(
          {Agent,
           fn ->
             %{
               discovery_calls: [],
               discovery_responses: [{:ok, %{"tools" => [tool(identity)]}}],
               invocations: [],
               responses: [response]
             }
           end},
          restart: :temporary
        )
      )

    client
  end

  defp configured!(identity, client) do
    {:ok, configured} =
      ConfiguredIntegration.new(
        scope: {:tenant, identity.tenant_id},
        integration_id: identity.integration_id,
        configuration_generation: identity.configuration_generation,
        credential_generation: identity.credential_generation,
        catalog_generation: identity.catalog_generation,
        allowed_tools: [identity.remote_name],
        client_config: [
          endpoint: identity.endpoint,
          test_client: client,
          test_observer: self()
        ]
      )

    configured
  end

  defp load!(configured) do
    {:ok, integration} =
      CatalogLoader.load(configured,
        connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
        protocol: Vxpipe.CallEngine.TestRemoteMCPCatalogProtocolClient
      )

    integration
  end

  defp catalog!(identity, integration) do
    {:ok, catalog} =
      IntegrationCatalog.new(
        application: %{},
        tenants: %{identity.tenant_id => %{identity.integration_id => integration}}
      )

    catalog
  end

  defp resolve!(catalog, identity) do
    {:ok, resolved} =
      IntegrationCatalog.resolve(
        catalog,
        identity.tenant_id,
        identity.integration_id,
        identity.remote_name
      )

    resolved
  end

  defp start_owner!(supervisor, identity, catalog, binding) do
    {:ok, owner} =
      DynamicSupervisor.start_child(
        supervisor,
        {IntegrationOwner,
         activation_id: "activation-#{identity.catalog_generation}",
         integrations: catalog,
         tools: %{identity.local_name => binding},
         connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
         protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
      )

    owner
  end

  defp tool(identity) do
    %{
      "name" => identity.remote_name,
      "description" => "Controlled churn operation.",
      "inputSchema" => %{
        "$schema" => "https://json-schema.org/draft/2020-12/schema",
        "type" => "object",
        "properties" => %{identity.field_name => %{"type" => "string"}},
        "required" => [identity.field_name],
        "additionalProperties" => false
      }
    }
  end

  defp result(identity) do
    "result-" <> String.replace_prefix(identity.catalog_generation, "catalog-", "")
  end

  defp atomized_external_values(range) do
    Enum.flat_map(range, fn index ->
      index
      |> identity()
      |> Map.values()
      |> Enum.filter(&(not atom_missing?(&1)))
    end)
  end

  defp atom_missing?(value) do
    _existing = String.to_existing_atom(value)
    false
  rescue
    ArgumentError -> true
  end

  defp loaded_modules do
    :code.all_loaded()
    |> Enum.map(fn {module, _path} -> module end)
    |> MapSet.new()
  end
end
