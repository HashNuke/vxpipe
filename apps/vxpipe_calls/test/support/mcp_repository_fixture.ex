defmodule Vxpipe.Calls.Test.MCPRepositoryFixture do
  def find_identity(_context, _tenant, _identity), do: {:ok, nil}

  def fetch_tenant({_owner, :missing}, _tenant), do: {:error, :not_found}

  def fetch_tenant(_owner, tenant),
    do:
      {:ok,
       %Vxpipe.Calls.Tenant{key: tenant, name: "Tenant", inserted_at: ~U[2026-11-06 00:00:00Z]}}

  def create({_owner, :duplicate_revoked}, _tenant, _attributes, _secrets),
    do: {:error, {:mcp_connection_exists, "revoked-connection"}}

  def create(owner, tenant, attributes, secrets) do
    send(owner, {:mcp_create, tenant, attributes, secrets})

    {:ok,
     Map.merge(attributes, %{
       id: "connection-id",
       tenant_key: tenant,
       generation: 1,
       status: "connected",
       secrets: secrets
     })}
  end

  def get(_owner, tenant, id) do
    {:ok,
     %{
       id: id,
       tenant_key: tenant,
       catalog: [%{"name" => "list_events"}],
       secrets: %{"token" => "hidden"}
     }}
  end

  def list(owner, tenant) do
    send(owner, {:mcp_list, tenant})

    {:ok,
     [
       %{
         id: "connection-id",
         tenant_key: tenant,
         server_name: "Calendar",
         secrets: %{"token" => "private"}
       }
     ]}
  end

  def get_retained({owner, %{directory_entry: _} = connection}, tenant, id) do
    send(owner, {:mcp_metadata, tenant, id})
    {:ok, Map.merge(connection, %{id: id, tenant_key: tenant})}
  end

  def get_retained(context, tenant, id) do
    owner = if is_tuple(context), do: elem(context, 0), else: context
    send(owner, {:mcp_metadata, tenant, id})
    revoked? = id == "revoked-connection"

    {:ok,
     %{
       id: id,
       tenant_key: tenant,
       generation: if(revoked?, do: 4, else: 3),
       endpoint: "https://mcp.example.test/mcp",
       endpoint_identity: "https://mcp.example.test/mcp",
       auth_method: "bearer",
       status: if(revoked?, do: "revoked", else: "connected"),
       directory_id: nil,
       namespace: "stable",
       catalog: []
     }}
  end

  def resolve({owner, %{directory_entry: _} = connection}, tenant, id) do
    send(owner, {:mcp_resolve, tenant, id})

    {:ok,
     %Vxpipe.Calls.ResolvedMCPConnection{
       connection: Map.merge(connection, %{id: id, tenant_key: tenant}),
       secrets: %{"token" => "saved-secret"}
     }}
  end

  def resolve({owner, :unreadable}, tenant, id) do
    send(owner, {:mcp_resolve, tenant, id})
    {:error, :mcp_credentials_unavailable}
  end

  def resolve(owner, tenant, id) do
    send(owner, {:mcp_resolve, tenant, id})

    {:ok,
     %Vxpipe.Calls.ResolvedMCPConnection{
       connection: %{
         id: id,
         tenant_key: tenant,
         generation: 3,
         endpoint: "https://mcp.example.test/mcp",
         auth_method: "bearer"
       },
       secrets: %{"token" => "saved-secret"}
     }}
  end

  def replace({owner, :unreadable}, tenant, id, generation, attributes, secrets),
    do: replace(owner, tenant, id, generation, attributes, secrets)

  def replace({owner, %{directory_entry: _}}, tenant, id, generation, attributes, secrets),
    do: replace(owner, tenant, id, generation, attributes, secrets)

  def replace(owner, tenant, id, generation, attributes, secrets) do
    send(owner, {:mcp_replace, tenant, id, generation, secrets})

    {:ok,
     Map.merge(attributes, %{
       id: id,
       tenant_key: tenant,
       generation: generation + 1,
       status: "connected",
       namespace: "stable"
     })}
  end

  def revoke(owner, tenant, id, generation) do
    send(owner, {:mcp_revoke, tenant, id, generation})
    {:ok, %{id: id, tenant_key: tenant, generation: generation + 1, status: "revoked"}}
  end

  def refresh_catalog(owner, tenant, id, generation, _freshness, attributes) do
    send(owner, {:mcp_catalog, tenant, id, generation, attributes})

    with {:ok, metadata} <- get_retained(owner, tenant, id),
         do: {:ok, Map.merge(metadata, attributes)}
  end
end
