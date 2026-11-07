defmodule Vxpipe.Calls.Test.MCPOAuthReconnectFixture do
  use Agent
  alias Vxpipe.Calls.{PreparedMCPOAuth, ResolvedMCPConnection, ResolvedMCPOAuthAttempt}

  def start_link(owner) do
    Agent.start_link(fn ->
      %{
        owner: owner,
        tenant: "AAAAAAAAAAAAAAAA",
        attempt: nil,
        completion: :ok,
        connection: %{
          id: "connection",
          tenant_key: "AAAAAAAAAAAAAAAA",
          generation: 7,
          status: "connected",
          auth_method: "oauth",
          endpoint: "https://mcp.test/mcp",
          directory_id: "directory-calendar",
          namespace: "retained-namespace"
        },
        secrets: %{
          "access_token" => "working-access",
          "refresh_token" => "working-refresh",
          "registration_method" => "dcr",
          "scopes" => ["tools:read"],
          "client_id" => "registered",
          "auth_method" => "none",
          "issuer" => "https://auth.test",
          "resource" => "https://mcp.test/mcp",
          "redirect_uri" => "https://console.test/oauth/mcp/callback"
        }
      }
    end)
  end

  def snapshot(pid), do: Agent.get(pid, & &1)

  def listing(pid, entry),
    do:
      Agent.update(pid, fn state ->
        %{
          state
          | connection:
              Map.merge(state.connection, %{
                directory_entry: entry,
                directory_id: entry["directory_id"] <> "/" <> entry["integration_id"]
              })
        }
      end)

  def prepare_saved(pid, tenant, input, origin, registration, entry) do
    send(snapshot(pid).owner, {:prepared_saved, input, registration, entry})
    {:ok, prepared} = prepare_reconnect(pid, tenant, input, origin, registration)
    {:ok, %{prepared | secrets: Map.put(prepared.secrets, "directory_entry", entry)}}
  end

  def completion(pid, mode), do: Agent.update(pid, &%{&1 | completion: mode})
  def fail_resolve(pid, reason), do: Agent.update(pid, &Map.put(&1, :resolve_error, reason))

  def change(pid, status, auth_method \\ "oauth"),
    do:
      Agent.update(
        pid,
        &%{
          &1
          | connection: %{&1.connection | generation: 8, status: status, auth_method: auth_method},
            secrets: %{"access_token" => "newer-access"}
        }
      )

  def resolve(pid, tenant, id) do
    state = snapshot(pid)
    send(state.owner, :resolved)

    cond do
      state.tenant != tenant or state.connection.id != id -> {:error, :mcp_connection_not_found}
      state.connection.status == "revoked" -> {:error, :mcp_connection_revoked}
      state[:resolve_error] -> {:error, state.resolve_error}
      true -> {:ok, %ResolvedMCPConnection{connection: state.connection, secrets: state.secrets}}
    end
  end

  def get(pid, tenant, id) do
    with {:ok, resolved} <- resolve(pid, tenant, id), do: {:ok, resolved.connection}
  end

  def get_retained(pid, tenant, id) do
    state = snapshot(pid)

    if state.tenant == tenant and state.connection.id == id,
      do: {:ok, state.connection},
      else: {:error, :mcp_connection_not_found}
  end

  def prepare_reconnect(pid, _tenant, input, origin, registration) do
    send(snapshot(pid).owner, {:prepared_reconnect, input, registration})

    {:ok,
     %PreparedMCPOAuth{
       authorization_url: "https://auth.test/authorize",
       attributes: %{
         state: String.duplicate("s", 43),
         issuer: "https://auth.test",
         redirect_uri: origin <> "/oauth/mcp/callback",
         resource: input["endpoint"],
         draft_revision: "draft"
       },
       secrets: %{"code_verifier" => "private-verifier"}
     }}
  end

  def issue(pid, tenant, attributes, secrets) do
    Agent.update(
      pid,
      &%{
        &1
        | attempt: %ResolvedMCPOAuthAttempt{
            attempt: Map.put(attributes, :id, "attempt"),
            secrets: secrets
          }
      }
    )

    send(snapshot(pid).owner, {:issued, tenant, attributes})
    {:ok, %{id: "attempt"}}
  end

  def locate(pid, _state, _authority), do: {:ok, snapshot(pid).tenant}
  def claim(pid, _tenant, _state, _authority), do: {:ok, snapshot(pid).attempt}

  def complete(pid, _tenant, _callback, claimed) do
    state = snapshot(pid)
    send(state.owner, :completed)
    if state.completion == :change, do: change(pid, "connected")

    if state.completion == :deny do
      {:error, :oauth_consent_denied}
    else
      entry = claimed.secrets["directory_entry"]

      connection = %{
        id: claimed.attempt.connection_id,
        generation: claimed.attempt.generation,
        endpoint: claimed.attempt.resource,
        auth_method: "oauth",
        directory_id: nil,
        server_name: "Calendar"
      }

      connection =
        if entry,
          do:
            Map.merge(connection, %{
              directory_entry: entry,
              directory_id: entry["directory_id"] <> "/" <> entry["integration_id"],
              server_name: entry["name"]
            }),
          else: connection

      connection =
        case state.completion do
          {:tamper, values} -> Map.merge(connection, values)
          _ -> connection
        end

      {:ok,
       %ResolvedMCPConnection{
         connection: connection,
         secrets: %{"access_token" => "replacement-access"}
       }}
    end
  end

  def replace(pid, tenant, id, generation, attributes, secrets) do
    Agent.get_and_update(pid, fn state ->
      if state.tenant == tenant and state.connection.id == id and
           state.connection.generation == generation and
           state.connection.status in ["connected", "revoked"] do
        connection =
          Map.merge(
            state.connection,
            Map.merge(attributes, %{generation: generation + 1, status: "connected"})
          )

        {{:ok, connection}, %{state | connection: connection, secrets: secrets}}
      else
        {{:error, :stale_mcp_connection}, state}
      end
    end)
  end
end
