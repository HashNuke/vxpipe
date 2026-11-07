defmodule Vxpipe.Console.Test.MCPRuntimeNodeCase do
  @moduledoc false
  use ExUnit.CaseTemplate
  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Vxpipe.Calls.Administration
  alias Vxpipe.Console.Test.{MCPNodeHTTP, MCPRuntimeNode, OutboundMCPOAuthServer}
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, Repo}
  alias Vxpipe.Persistence.MCP.ConnectionStore
  alias Vxpipe.Persistence.Schema.Tenant

  using do
    quote do
      import Vxpipe.Console.Test.MCPRuntimeNodeCase
      alias Vxpipe.Console.Test.{MCPRuntimeNode, OutboundMCPOAuthServer}
      @moduletag :integration
    end
  end

  setup_all do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    :ok
  end

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)

    {:ok, keyring} =
      CredentialKeyring.new("node-test", %{"node-test" => :crypto.strong_rand_bytes(32)})

    context = [repo: Repo, keyring: keyring]
    tenant = tenant()
    other_tenant = tenant()

    state =
      start_supervised!(
        {Agent,
         fn ->
           OutboundMCPOAuthServer.initial("own_client") |> Map.put(:hold_tokens, false)
         end}
      )

    server =
      start_supervised!(
        {Bandit, plug: {MCPNodeHTTP, %{owner: self(), state: state}}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    base = "http://127.0.0.1:#{port}"
    connection = connection(context, tenant, state, "node-client")
    other = connection(context, other_tenant, state, "other-client")

    nodes =
      for index <- 0..1 do
        peer =
          start_supervised!(%{
            id: {:mcp_runtime_node, index},
            start:
              {:peer, :start_link,
               [%{connection: :standard_io, args: [~c"+S", ~c"2:2", ~c"-pa" | :code.get_path()]}]},
            restart: :temporary
          })

        {peer, :peer.call(peer, MCPRuntimeNode, :boot, [Repo.config(), context, base], 30_000)}
      end

    [{first, first_identity}, {second, second_identity}] = nodes
    assert first_identity.os_pid != second_identity.os_pid
    assert first_identity.backend != second_identity.backend
    refute System.pid() in [first_identity.os_pid, second_identity.os_pid]

    %{
      context: context,
      tenant: tenant,
      other_tenant: other_tenant,
      id: connection.id,
      other_id: other.id,
      state: state,
      base: base,
      first: first,
      second: second
    }
  end

  def rpc(peer, function, args \\ []),
    do: :peer.call(peer, MCPRuntimeNode, function, args, 15_000)

  def saved(data), do: ConnectionStore.resolve(data.context, data.tenant, data.id)
  def tokens(data), do: OutboundMCPOAuthServer.count(data.state, {"POST", "/token"})
  def hold(data, value), do: Agent.update(data.state, &%{&1 | hold_tokens: value})

  def async(label, operation) do
    owner = self()

    start_supervised!(
      {Task,
       fn ->
         result =
           try do
             operation.()
           catch
             _, _ -> {:error, :node_stopped}
           end

         send(owner, {label, result})
       end},
      id: {:node_operation, label}
    )
  end

  def open(data) do
    assert :ok = rpc(data.first, :open, [data.tenant, data.id, data.base])
    assert_receive {:node_sse_stream, stream, []}, 5_000

    assert_receive {:node_mcp_request, "GET", ["Bearer node-client-access"], ["node-workspace"]},
                   5_000

    flush_protocol()
    stream
  end

  def flush_protocol do
    receive do
      {:node_mcp_request, _, _, _} -> flush_protocol()
      {:node_rpc, _} -> flush_protocol()
    after
      0 -> :ok
    end
  end

  defp tenant do
    {:ok, tenant, _} =
      Administration.bootstrap_tenant("MCP node acceptance", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      Repo.delete_all(from(t in Tenant, where: t.key == ^tenant.key))
      Sandbox.checkin(Repo)
    end)

    tenant.key
  end

  defp connection(context, tenant, state, client) do
    secret = "synthetic-node-client-secret"
    refresh = client <> "-refresh"
    access = client <> "-access"

    Agent.update(state, fn s ->
      %{
        s
        | clients:
            Map.put(s.clients, client, %{
              "token_endpoint_auth_method" => "client_secret_basic",
              "client_secret" => secret
            }),
          refresh: Map.put(s.refresh, refresh, client),
          access: MapSet.put(s.access, access)
      }
    end)

    {:ok, connection} =
      ConnectionStore.create_oauth(
        context,
        tenant,
        Ecto.UUID.generate(),
        %{
          endpoint: OutboundMCPOAuthServer.resource(),
          endpoint_identity: OutboundMCPOAuthServer.resource(),
          server_name: "Node tools",
          auth_method: "oauth",
          catalog: []
        },
        %{
          "registration_method" => "own_client",
          "grant_type" => "authorization_code",
          "auth_method" => "client_secret_basic",
          "client_id" => client,
          "client_secret" => secret,
          "token_endpoint" => OutboundMCPOAuthServer.issuer() <> "/token",
          "issuer" => OutboundMCPOAuthServer.issuer(),
          "resource" => OutboundMCPOAuthServer.resource(),
          "access_token" => access,
          "refresh_token" => refresh,
          "expires_at" => DateTime.utc_now() |> DateTime.add(300) |> DateTime.to_iso8601(),
          "headers" => [%{"name" => "X-Workspace", "value" => "node-workspace"}]
        }
      )

    connection
  end
end
