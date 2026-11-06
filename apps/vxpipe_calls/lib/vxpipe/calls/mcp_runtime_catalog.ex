defmodule Vxpipe.Calls.MCPRuntimeCatalog do
  @moduledoc "Private startup bindings for saved tenant MCP tools selected by a prepared call."

  alias Vxpipe.CallEngine.RemoteMCP.IntegrationCatalog

  alias Vxpipe.Calls.{
    MCPTransportCredentials,
    Repositories,
    ResolvedMCPConnection,
    SavedMCPCompilationCatalog
  }

  alias Vxpipe.MCP.{RuntimeAuthProvider, StaticConfiguration}

  def build(plan, options) do
    selected = selected_tools(plan)

    with true <- Enum.all?(selected, &(&1.scope == {:tenant, plan.tenant_id})),
         {:ok, integrations} <- resolve(plan.tenant_id, selected, options),
         {:ok, catalog} <- IntegrationCatalog.new(tenants: %{plan.tenant_id => integrations}),
         true <- Enum.all?(selected, &match?({:ok, _}, IntegrationCatalog.checkout(catalog, &1))) do
      {:ok, catalog}
    else
      _ -> {:error, :mcp_connection_unavailable}
    end
  rescue
    _ -> {:error, :mcp_connection_unavailable}
  catch
    :exit, _ -> {:error, :mcp_connection_unavailable}
  end

  defp selected_tools(plan) do
    for {_key, participant} <- plan.participants,
        {_name, %{type: :mcp, remote: remote}} <- participant.tools,
        do: remote
  end

  defp resolve(tenant, selected, options) do
    selected
    |> Enum.uniq_by(&{&1.integration_id, &1.configuration_generation})
    |> Enum.reduce_while({:ok, %{}}, fn remote, {:ok, integrations} ->
      with {generation, ""} <- Integer.parse(remote.configuration_generation),
           {:ok, repository} <- Repositories.fetch(options, :mcp_connection_repository),
           {:ok, %ResolvedMCPConnection{} = saved} <-
             Repositories.call(repository, :resolve, [tenant, remote.integration_id]),
           true <-
             saved.connection.tenant_key == tenant and
               saved.connection.id == remote.integration_id and
               saved.connection.generation == generation and
               saved.connection.status == "connected",
           {:ok, integration} <- SavedMCPCompilationCatalog.integration(saved.connection),
           {:ok, configuration} <- configuration(saved),
           {:ok, resolver} <- runtime_resolver(options),
           {:ok, runtime_authentication} <-
             RuntimeAuthProvider.init(%{
               tenant: tenant,
               connection_id: remote.integration_id,
               generation: generation,
               auth_method: saved.connection.auth_method,
               endpoint: configuration.endpoint,
               resolver: resolver
             }) do
        private = %{
          integration
          | client_config: [
              endpoint: configuration.endpoint,
              authentication: :none,
              runtime_authentication: runtime_authentication
            ]
        }

        {:cont, {:ok, Map.put(integrations, remote.integration_id, private)}}
      else
        _ -> {:halt, {:error, :mcp_connection_unavailable}}
      end
    end)
  end

  defp configuration(%ResolvedMCPConnection{connection: %{auth_method: "oauth"}} = saved) do
    # Resolve OAuth tokens only at submission, after validating the selected schema.
    # Extra MCP headers must not shadow the runtime provider's Authorization header.
    headers = Map.get(saved.secrets, "headers", [])

    with {:ok, _validated} <-
           StaticConfiguration.new(%{
             "endpoint" => saved.connection.endpoint,
             "auth_method" => "bearer",
             "credentials" => %{"token" => "validation-placeholder", "headers" => headers}
           }) do
      StaticConfiguration.new(%{
        "endpoint" => saved.connection.endpoint,
        "auth_method" => if(headers == [], do: "none", else: "headers"),
        "credentials" => if(headers == [], do: %{}, else: %{"headers" => headers})
      })
    end
  end

  defp configuration(saved) do
    StaticConfiguration.new(%{
      "endpoint" => saved.connection.endpoint,
      "auth_method" => saved.connection.auth_method,
      "credentials" => saved.secrets
    })
  end

  defp runtime_resolver(options) do
    case Keyword.fetch(options, :mcp_runtime_resolver) do
      {:ok, {module, context} = resolver} when is_atom(module) ->
        if nonsecret_context?(context),
          do: {:ok, resolver},
          else: {:error, :invalid_runtime_source}

      :error ->
        keys = [:mcp_connection_repository, :mcp_oauth_grant_repository, :mcp_oauth_refresh]

        if not Keyword.has_key?(options, :now) and
             Enum.all?(keys, &(Repositories.fetch(options, &1) == Repositories.fetch([], &1))),
           do: {:ok, {MCPTransportCredentials, :configured}},
           else: {:error, :invalid_runtime_source}

      _ ->
        {:error, :invalid_runtime_source}
    end
  end

  defp nonsecret_context?(value) when is_pid(value) or is_reference(value), do: true

  defp nonsecret_context?(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.all?(&nonsecret_context?/1)

  defp nonsecret_context?(_), do: false
end
