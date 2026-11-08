defmodule Vxpipe.Console.Test.MCPManagementFixture do
  def resolve_target(_owner, tenant, input),
    do: Vxpipe.Console.MCPConnectionTarget.resolve([], tenant, input)

  def find_identity(_owner, tenant, %{endpoint_identity: endpoint})
      when endpoint in ["https://mcp.example.test/existing", "https://mcp.example.test/revoked"] do
    revoked? = String.ends_with?(endpoint, "/revoked")

    {:ok,
     %{
       id: if(revoked?, do: "revoked-connection", else: "existing-connection"),
       tenant_key: tenant,
       endpoint_identity: endpoint,
       directory_id: nil,
       generation: 4,
       status: if(revoked?, do: "revoked", else: "connected")
     }}
  end

  def find_identity(_owner, _tenant, _identity), do: {:ok, nil}

  def prepare_target(owner, tenant, input, origin, _target),
    do: prepare(owner, tenant, input, origin)

  def locate(_owner, state, _authority) do
    if state == String.duplicate("x", 43),
      do: {:error, :oauth_attempt_unavailable},
      else: {:ok, "AAAAAAAAAAAAAAAA"}
  end

  def claim(owner, tenant, state, authority) do
    send(owner, {:oauth_claimed, tenant})

    {:ok,
     %Vxpipe.Calls.ResolvedMCPOAuthAttempt{
       attempt: %{
         id: "attempt-id",
         return_to:
           if(state == String.duplicate("r", 43),
             do: "/t/" <> tenant <> "/services/search?q=calendar&cursor=page-2",
             else: nil
           ),
         connection_id: "connection-id",
         generation: 1,
         installation_revision: authority.installation_revision,
         redirect_uri: authority.redirect_uri
       },
       secrets: %{}
     }}
  end

  def complete(_owner, _tenant, %{error: "access_denied"}, _claimed),
    do: {:error, :oauth_consent_denied}

  def complete(_owner, _tenant, %{code: "check-failed"}, _claimed),
    do: {:error, :mcp_connection_failed}

  def complete(owner, tenant, _callback, _claimed) do
    send(owner, {:oauth_completed, tenant})

    {:ok,
     %Vxpipe.Calls.ResolvedMCPConnection{
       connection: %{id: "connection-id", generation: 1, auth_method: "oauth"},
       secrets: %{"access_token" => "private-token"}
     }}
  end

  def create_oauth(owner, tenant, id, attributes, _secrets) do
    send(owner, {:oauth_connection_saved, tenant})
    {:ok, Map.merge(attributes, %{id: id, tenant_key: tenant})}
  end

  def prepare(_owner, _tenant, %{"revision" => "busy"}, _origin),
    do: {:error, :mcp_connection_busy}

  def prepare(_owner, _tenant, %{"revision" => "invalid-own"}, _origin),
    do: {:error, :invalid_own_oauth_configuration}

  def prepare(_owner, _tenant, %{"revision" => "machine-grant"}, _origin),
    do: {:error, :oauth_browser_grant_required}

  def prepare(owner, tenant, input, origin) do
    send(owner, {:oauth_preparation_input, input})
    send(owner, {:oauth_prepared, tenant})

    {:ok,
     %Vxpipe.Calls.PreparedMCPOAuth{
       authorization_url: "https://auth.example.test/authorize?state=opaque",
       attributes: %{
         state: String.duplicate("s", 43),
         issuer: "https://auth.example.test",
         redirect_uri: origin <> "/oauth/mcp/callback",
         resource: input["endpoint"],
         draft_revision: input["revision"]
       },
       secrets: %{"code_verifier" => "private-verifier"}
     }}
  end

  def issue(owner, tenant, attributes, _secrets) do
    send(owner, {:oauth_attempt_saved, tenant, attributes})
    {:ok, %{id: "attempt-id"}}
  end

  def fetch_tenant(_owner, tenant),
    do:
      {:ok,
       %Vxpipe.Calls.Tenant{key: tenant, name: "Tenant", inserted_at: ~U[2026-11-06 00:00:00Z]}}

  def discover(owner, tenant, input) do
    send(owner, {:mcp_preflight, tenant})
    {:ok, %{endpoint: input["endpoint"], revision: input["revision"], outcome: :unknown}}
  end

  def prepare_reconnect(owner, tenant, input, origin, registration) do
    send(owner, {:oauth_registration, registration})
    prepare(owner, tenant, input, origin)
  end

  def resolve(_owner, tenant, "oauth-connection") do
    {:ok,
     %Vxpipe.Calls.ResolvedMCPConnection{
       connection: %{
         id: "oauth-connection",
         tenant_key: tenant,
         generation: 7,
         endpoint: "https://mcp.example.test/mcp",
         auth_method: "oauth",
         status: "connected",
         directory_id: nil
       },
       secrets: %{"client_id" => "registered", "access_token" => "private-token"}
     }}
  end

  def get(owner, tenant, "oauth-connection") do
    with {:ok, resolved} <- resolve(owner, tenant, "oauth-connection"),
         do:
           {:ok,
            Map.put(resolved.connection, :oauth, %{
              "registration_method" => "dcr",
              "grant_type" => "authorization_code",
              "auth_method" => "none"
            })}
  end

  def get(_owner, tenant, id) do
    {:ok,
     %{
       id: id,
       tenant_key: tenant,
       catalog: [%{"name" => "list_events"}],
       secrets: %{"token" => "hidden-secret"}
     }}
  end

  def get_retained(owner, tenant, id), do: get(owner, tenant, id)

  def refresh_catalog(owner, tenant, id, generation, _freshness, attributes) do
    send(owner, {:mcp_catalog_saved, tenant, id, generation, attributes})

    {:ok,
     Map.merge(attributes, %{
       id: id,
       tenant_key: tenant,
       generation: generation,
       auth_method: "oauth"
     })}
  end

  def list(_owner, _tenant), do: {:ok, []}

  def check(owner, tenant, input) do
    send(owner, {:mcp_checked, tenant})

    {:ok,
     %Vxpipe.Calls.ResolvedMCPConnection{
       connection: %{
         endpoint: input["endpoint"],
         endpoint_identity: input["endpoint"],
         server_name: "Calendar",
         auth_method: input["auth_method"],
         catalog: [],
         directory_id: nil
       },
       secrets: input["credentials"]
     }}
  end

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
end
