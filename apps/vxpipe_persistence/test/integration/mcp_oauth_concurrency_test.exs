defmodule Vxpipe.Persistence.Integration.MCPOAuthConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias Vxpipe.Calls.Administration
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, Repo}
  alias Vxpipe.Persistence.MCP.{ConnectionStore, OAuthAttemptStore, OAuthGrantStore}
  alias Vxpipe.Persistence.Schema.{MCPOAuthAttempt, Tenant}
  alias Vxpipe.Persistence.Test.MCPDatabaseNode
  @moduletag :integration
  @now ~U[2026-11-06 12:00:00.000000Z]

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)

    {:ok, tenant, _} =
      Administration.bootstrap_tenant("MCP attempt race", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    {:ok, keyring} = CredentialKeyring.new("race", %{"race" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keyring, now: MCPDatabaseNode.clock(@now)]

    attributes = %{
      connection_id: Ecto.UUID.generate(),
      generation: 1,
      user_id: "user",
      session_id: "session",
      issuer: "https://auth.example.test",
      redirect_uri: "https://console.example.test/oauth/mcp/callback",
      resource: "https://mcp.example.test/mcp",
      draft_revision: "draft",
      installation_revision: 1,
      expires_at: DateTime.add(@now, 300),
      state: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    }

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      Repo.delete_all(from(t in Tenant, where: t.key == ^tenant.key))
      Sandbox.checkin(Repo)
    end)

    %{
      tenant: tenant.key,
      context: context,
      attributes: attributes,
      authority:
        Map.take(attributes, [:user_id, :session_id, :installation_revision, :redirect_uri])
    }
  end

  test "independent BEAM nodes claim one attempt only once", data do
    assert {:ok, _} =
             OAuthAttemptStore.issue(data.context, data.tenant, data.attributes, %{
               "verifier" => "race-private"
             })

    results = race(List.duplicate(claim_operation(data), 2))
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :oauth_attempt_unavailable})) == 1
    assert {:error, :oauth_attempt_unavailable} = claim(data)

    assert Repo.one!(
             from(a in MCPOAuthAttempt,
               where: a.state_digest == ^digest(data.attributes.state),
               select: is_nil(a.encrypted_payload)
             )
           )
  end

  test "cleanup racing with claim preserves a pending attempt's single successful claim", data do
    assert {:ok, _} = OAuthAttemptStore.issue(data.context, data.tenant, data.attributes, %{})

    [claim, {:ok, progress}] =
      race([claim_operation(data), {OAuthAttemptStore, :prune, [data.context, 500]}])

    assert {:ok, _} = claim
    assert progress.processed in [0, 1]
    assert {:error, :oauth_attempt_unavailable} = claim(data)
  end

  test "independent BEAM nodes enforce the tenant pending-attempt cap", data do
    for index <- 1..7 do
      assert {:ok, _} =
               OAuthAttemptStore.issue(
                 data.context,
                 data.tenant,
                 %{data.attributes | state: data.attributes.state <> Integer.to_string(index)},
                 %{}
               )
    end

    results =
      race(
        Enum.map(["a", "b"], fn suffix ->
          {OAuthAttemptStore, :issue,
           [
             data.context,
             data.tenant,
             %{data.attributes | state: data.attributes.state <> suffix},
             %{}
           ]}
        end)
      )

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :oauth_attempt_busy})) == 1
  end

  test "independent BEAM nodes acquire only one refresh claim", data do
    connection = connection(data)
    operation = {OAuthGrantStore, :claim, [data.context, data.tenant, connection.id, 1, 1]}
    results = race([operation, operation])
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :oauth_refresh_in_progress})) == 1
    {:ok, claim} = Enum.find(results, &match?({:ok, _}, &1))

    assert :ok =
             OAuthGrantStore.complete(data.context, data.tenant, connection.id, 1, claim.id, %{
               "access_token" => "new-access",
               "refresh_token" => "new-refresh"
             })

    assert {:error, :stale_oauth_grant} =
             OAuthGrantStore.claim(data.context, data.tenant, connection.id, 1, 1)

    assert {:ok, saved} = ConnectionStore.resolve(data.context, data.tenant, connection.id)
    assert saved.secrets["grant_revision"] == 2
    assert saved.secrets["refresh_token"] == "new-refresh"
    assert saved.connection.generation == 1
  end

  test "refresh completion racing revocation never revives the connection", data do
    connection = connection(data)
    assert {:ok, claim} = OAuthGrantStore.claim(data.context, data.tenant, connection.id, 1, 1)

    [completion, revoked] =
      race([
        {OAuthGrantStore, :complete,
         [
           data.context,
           data.tenant,
           connection.id,
           1,
           claim.id,
           %{"access_token" => "new-access", "refresh_token" => "new-refresh"}
         ]},
        {ConnectionStore, :revoke, [data.context, data.tenant, connection.id, 1]}
      ])

    assert completion in [:ok, {:error, :oauth_connection_unavailable}]
    assert {:ok, %{status: "revoked", generation: 2}} = revoked

    assert {:error, :mcp_connection_revoked} =
             ConnectionStore.resolve(data.context, data.tenant, connection.id)
  end

  test "a node cannot complete its held refresh after another node revokes", data do
    connection = connection(data)
    {first, first_identity} = database_node(0)
    {second, second_identity} = database_node(1)
    assert_distinct_nodes([first_identity, second_identity])
    identity = [data.context, data.tenant, connection.id, 1]

    assert {:ok, claim} = :peer.call(first, OAuthGrantStore, :claim, identity ++ [1])

    assert {:ok, %{status: "revoked", generation: 2}} =
             :peer.call(second, ConnectionStore, :revoke, identity)

    assert {:error, :oauth_connection_unavailable} =
             :peer.call(
               first,
               OAuthGrantStore,
               :complete,
               identity ++ [claim.id, %{"access_token" => "late-access"}]
             )

    assert {:error, :mcp_connection_revoked} =
             :peer.call(first, ConnectionStore, :resolve, Enum.take(identity, 3))
  end

  test "a crashed claimant leaves a durable fence that another node cannot reclaim", data do
    connection = connection(data)
    assert {:ok, before} = ConnectionStore.resolve(data.context, data.tenant, connection.id)
    {first, first_identity} = database_node(0)
    {second, second_identity} = database_node(1)
    assert_distinct_nodes([first_identity, second_identity])
    identity = [data.context, data.tenant, connection.id, 1]
    assert {:ok, claim} = :peer.call(first, OAuthGrantStore, :claim, identity ++ [1])
    monitor = Process.monitor(first)
    :peer.cast(first, :erlang, :halt, [137])
    assert_receive {:DOWN, ^monitor, :process, ^first, _reason}, 5_000

    assert {:error, :oauth_refresh_in_progress} =
             :peer.call(second, OAuthGrantStore, :claim, identity ++ [1])

    expired = Keyword.put(data.context, :now, MCPDatabaseNode.clock(DateTime.add(@now, 30)))
    expired_identity = [expired, data.tenant, connection.id, 1]

    assert {:error, :oauth_reconnect_required} =
             :peer.call(second, OAuthGrantStore, :claim, expired_identity ++ [1])

    assert {:error, :oauth_reconnect_required} =
             :peer.call(
               second,
               OAuthGrantStore,
               :complete,
               expired_identity ++ [claim.id, %{"access_token" => "late-access"}]
             )

    assert {:ok, saved} =
             :peer.call(second, ConnectionStore, :resolve, Enum.take(identity, 3))

    assert Map.delete(saved.secrets, "refresh_claim") == before.secrets
    assert saved.secrets["refresh_claim"]["id"] == claim.id
    assert saved.connection.generation == 1
  end

  defp connection(data) do
    attributes = %{
      endpoint: "https://mcp.example.test/mcp",
      endpoint_identity: "https://mcp.example.test/mcp",
      server_name: "Tools",
      auth_method: "oauth",
      catalog: []
    }

    {:ok, connection} =
      ConnectionStore.create_oauth(data.context, data.tenant, Ecto.UUID.generate(), attributes, %{
        "access_token" => "old-access",
        "refresh_token" => "old-refresh"
      })

    connection
  end

  defp claim(data),
    do: OAuthAttemptStore.claim(data.context, data.tenant, data.attributes.state, data.authority)

  defp claim_operation(data),
    do:
      {OAuthAttemptStore, :claim,
       [data.context, data.tenant, data.attributes.state, data.authority]}

  defp digest(state), do: :crypto.hash(:sha256, state)

  defp race(operations) do
    observer = self()
    nodes = operations |> Enum.with_index() |> Enum.map(fn {_, index} -> database_node(index) end)

    workers =
      operations
      |> Enum.zip(nodes)
      |> Enum.with_index()
      |> Enum.map(fn {{{module, function, arguments}, {peer, identity}}, index} ->
        pid =
          start_supervised!(
            {Task,
             fn ->
               send(observer, {:ready, self(), identity})

               receive do
                 :run ->
                   send(
                     observer,
                     {:result, self(), :peer.call(peer, module, function, arguments)}
                   )
               after
                 5_000 -> send(observer, {:result, self(), {:error, :test_timeout}})
               end
             end},
            id: {:attempt_racer, index}
          )

        {pid, Process.monitor(pid)}
      end)

    identities =
      Enum.map(workers, fn {pid, _monitor} ->
        assert_receive {:ready, ^pid, identity}, 5_000
        identity
      end)

    assert_distinct_nodes(identities)
    Enum.each(workers, fn {pid, _monitor} -> send(pid, :run) end)

    Enum.map(workers, fn {pid, monitor} ->
      assert_receive {:result, ^pid, result}, 5_000
      assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 5_000
      result
    end)
  end

  defp database_node(index) do
    peer =
      start_supervised!(%{
        id: {:mcp_database_node, index},
        start:
          {:peer, :start_link,
           [%{connection: :standard_io, args: [~c"+S", ~c"2:2", ~c"-pa" | :code.get_path()]}]},
        restart: :temporary
      })

    {peer, :peer.call(peer, MCPDatabaseNode, :boot, [Repo.config()], 30_000)}
  end

  defp assert_distinct_nodes(identities) do
    assert length(Enum.uniq_by(identities, & &1.backend)) == length(identities)
    assert length(Enum.uniq_by(identities, & &1.os_pid)) == length(identities)
    refute Enum.any?(identities, &(&1.os_pid == System.pid()))
  end
end
