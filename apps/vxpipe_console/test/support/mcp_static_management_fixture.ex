defmodule Vxpipe.Console.Test.MCPStaticManagementFixture do
  alias Vxpipe.Calls.ResolvedMCPConnection

  def resolve_target(_owner, tenant, input),
    do: Vxpipe.Console.MCPConnectionTarget.resolve([], tenant, input)

  def find_identity(owner, tenant, identity) do
    send(owner, {:mcp_identity_lookup, tenant, identity})
    {:ok, nil}
  end

  def check_target(owner, tenant, input, target),
    do: check(owner, tenant, Map.put(input, "endpoint", target.endpoint))

  def fetch_tenant(_owner, tenant),
    do:
      {:ok,
       %Vxpipe.Calls.Tenant{key: tenant, name: "Tenant", inserted_at: ~U[2026-11-06 00:00:00Z]}}

  def discover(owner, tenant, input) do
    send(owner, {:mcp_preflight, tenant})
    {:ok, %{endpoint: input["endpoint"], revision: input["revision"], outcome: :unknown}}
  end

  def check(owner, tenant, input) do
    Vxpipe.Console.MCPConnectionProbe.check(
      [
        connection_check: fn _, _ ->
          send(owner, {:mcp_checked, tenant})
          {:ok, %{server_name: "Calendar", catalog: []}}
        end
      ],
      tenant,
      input
    )
  end

  def create(_owner, _tenant, %{endpoint: "https://mcp.example.test/revoked"}, _secrets),
    do: {:error, {:mcp_connection_exists, "revoked-connection"}}

  def create(owner, tenant, attributes, secrets) do
    send(owner, {:mcp_saved, tenant, secrets})

    {:ok,
     Map.merge(attributes, %{
       id: "019a50e0-0000-4000-8000-000000000001",
       tenant_key: tenant,
       generation: 1,
       status: "connected"
     })}
  end

  def get_retained(_owner, tenant, id) do
    revoked? = id == "revoked-connection"

    endpoint =
      if revoked?, do: "https://mcp.example.test/revoked", else: "https://mcp.example.test/mcp"

    {:ok,
     %{
       id: id,
       tenant_key: tenant,
       generation: if(revoked?, do: 4, else: 3),
       status: if(revoked?, do: "revoked", else: "connected"),
       endpoint: endpoint,
       endpoint_identity: endpoint,
       directory_id: nil,
       namespace: "stable",
       auth_method: "bearer",
       catalog: [%{"name" => "list_events"}]
     }}
  end

  def get(owner, tenant, id) do
    with {:ok, record} <- get_retained(owner, tenant, id),
         do: {:ok, Map.put(record, :secrets, %{"token" => "hidden-secret"})}
  end

  def resolve(owner, tenant, id) do
    send(owner, {:mcp_resolved, tenant, id})

    with {:ok, record} <- get_retained(owner, tenant, id),
         do:
           {:ok,
            %ResolvedMCPConnection{connection: record, secrets: %{"token" => "hidden-secret"}}}
  end

  def replace(owner, tenant, id, generation, attributes, secrets) do
    send(owner, {:mcp_replaced, tenant, id, generation, secrets})

    {:ok,
     Map.merge(attributes, %{
       id: id,
       tenant_key: tenant,
       generation: generation + 1,
       status: "connected",
       namespace: "stable"
     })}
  end

  def refresh_catalog(owner, tenant, id, generation, attributes) do
    send(owner, {:mcp_catalog_saved, tenant, id, generation, attributes})

    with {:ok, record} <- get_retained(owner, tenant, id),
         do: {:ok, Map.merge(record, attributes)}
  end

  def list(_owner, _tenant), do: {:ok, []}
end
