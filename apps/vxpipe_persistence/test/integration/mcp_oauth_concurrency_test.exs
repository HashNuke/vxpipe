defmodule Vxpipe.Persistence.Integration.MCPOAuthConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias Vxpipe.Calls.Administration
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, Repo}
  alias Vxpipe.Persistence.MCP.{ConnectionStore, OAuthAttemptStore, OAuthGrantStore}
  alias Vxpipe.Persistence.Schema.{MCPOAuthAttempt, Tenant}
  @moduletag :integration
  @now ~U[2026-11-06 12:00:00.000000Z]

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)

    {:ok, tenant, _} =
      Administration.bootstrap_tenant("MCP attempt race", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    {:ok, keyring} = CredentialKeyring.new("race", %{"race" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keyring, now: fn -> @now end]

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

  test "distinct database connections claim one attempt only once", data do
    assert {:ok, _} =
             OAuthAttemptStore.issue(data.context, data.tenant, data.attributes, %{
               "verifier" => "race-private"
             })

    results = race(List.duplicate(fn -> claim(data) end, 2))
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
      race([fn -> claim(data) end, fn -> OAuthAttemptStore.prune(data.context, 500) end])

    assert {:ok, _} = claim
    assert progress.processed in [0, 1]
    assert {:error, :oauth_attempt_unavailable} = claim(data)
  end

  test "distinct database connections enforce the tenant pending-attempt cap", data do
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
          fn ->
            OAuthAttemptStore.issue(
              data.context,
              data.tenant,
              %{data.attributes | state: data.attributes.state <> suffix},
              %{}
            )
          end
        end)
      )

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :oauth_attempt_busy})) == 1
  end

  test "distinct database connections acquire only one refresh claim", data do
    connection = connection(data)
    operation = fn -> OAuthGrantStore.claim(data.context, data.tenant, connection.id, 1, 1) end
    results = race([operation, operation])
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :oauth_refresh_in_progress})) == 1
    {:ok, claim} = Enum.find(results, &match?({:ok, _}, &1))

    assert :ok =
             OAuthGrantStore.complete(data.context, data.tenant, connection.id, 1, claim.id, %{
               "access_token" => "new-access",
               "refresh_token" => "new-refresh"
             })

    assert {:error, :stale_oauth_grant} = operation.()
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
        fn ->
          OAuthGrantStore.complete(data.context, data.tenant, connection.id, 1, claim.id, %{
            "access_token" => "new-access",
            "refresh_token" => "new-refresh"
          })
        end,
        fn -> ConnectionStore.revoke(data.context, data.tenant, connection.id, 1) end
      ])

    assert completion in [:ok, {:error, :oauth_connection_unavailable}]
    assert {:ok, %{status: "revoked", generation: 2}} = revoked

    assert {:error, :mcp_connection_revoked} =
             ConnectionStore.resolve(data.context, data.tenant, connection.id)
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

  defp digest(state), do: :crypto.hash(:sha256, state)

  defp race(operations) do
    observer = self()

    workers =
      operations
      |> Enum.with_index()
      |> Enum.map(fn {operation, index} ->
        pid =
          start_supervised!(
            {Task,
             fn ->
               :ok = Sandbox.checkout(Repo, sandbox: false)
               %{rows: [[connection]]} = Repo.query!("SELECT pg_backend_pid()")
               send(observer, {:ready, self(), connection})

               receive do
                 :run -> send(observer, {:result, self(), operation.()})
               after
                 5_000 -> send(observer, {:result, self(), {:error, :test_timeout}})
               end

               Sandbox.checkin(Repo)
             end},
            id: {:attempt_racer, index}
          )

        {pid, Process.monitor(pid)}
      end)

    connections =
      Enum.map(workers, fn {pid, _monitor} ->
        assert_receive {:ready, ^pid, connection}, 5_000
        connection
      end)

    assert length(Enum.uniq(connections)) == length(workers)
    Enum.each(workers, fn {pid, _monitor} -> send(pid, :run) end)

    Enum.map(workers, fn {pid, monitor} ->
      assert_receive {:result, ^pid, result}, 5_000
      assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 5_000
      result
    end)
  end
end
