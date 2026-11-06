defmodule Vxpipe.Persistence.MCP.OAuthGrantStoreTest do
  use Vxpipe.Persistence.DataCase, async: false
  alias Vxpipe.Calls.Administration
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, Repo}
  alias Vxpipe.Persistence.MCP.{ConnectionStore, OAuthGrantStore}
  @now ~U[2026-11-06 12:00:00.000000Z]

  setup do
    {:ok, tenant, _} =
      Administration.bootstrap_tenant("Refresh tenant", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    {:ok, keyring} = CredentialKeyring.new("key", %{"key" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keyring, now: fn -> @now end]

    attributes = %{
      endpoint: "https://mcp.test/mcp",
      endpoint_identity: "https://mcp.test/mcp",
      server_name: "Tools",
      auth_method: "oauth",
      catalog: []
    }

    {:ok, connection} =
      ConnectionStore.create_oauth(context, tenant.key, Ecto.UUID.generate(), attributes, %{
        "access_token" => "old-access",
        "refresh_token" => "old-refresh",
        "client_id" => "client",
        "client_secret_expires_at" => 2_000_000_000,
        "expires_at" => "2026-11-06T11:00:00Z",
        "scope" => "tools:read"
      })

    %{context: context, tenant: tenant.key, connection: connection}
  end

  test "repository outages return a fixed error and recovery preserves the refresh claim", data do
    {:ok, claim} = OAuthGrantStore.claim(data.context, data.tenant, data.connection.id, 1, 1)
    previous = Repo.get_dynamic_repo()
    name = Vxpipe.Persistence.MCPGrantRestartRepo
    repository = start_supervised!({Repo, name: name, pool_size: 1})
    monitor = Process.monitor(repository)
    stop_supervised!(Repo)
    assert_receive {:DOWN, ^monitor, :process, ^repository, :shutdown}

    try do
      for unavailable <- [name, repository] do
        Repo.put_dynamic_repo(unavailable)

        for operation <- grant_operations(data, data.context, claim.id) do
          assert {:error, :mcp_oauth_storage_unavailable} = operation.()
        end
      end
    after
      Repo.put_dynamic_repo(previous)
    end

    assert :ok =
             OAuthGrantStore.complete(
               data.context,
               data.tenant,
               data.connection.id,
               1,
               claim.id,
               %{"access_token" => "after-outage"}
             )

    assert {:ok, resolved} =
             ConnectionStore.resolve(data.context, data.tenant, data.connection.id)

    assert resolved.secrets["access_token"] == "after-outage"
  end

  test "programmer errors are not classified as grant storage outages", data do
    for operation <- grant_operations(data, Keyword.delete(data.context, :repo), "claim") do
      assert_raise KeyError, operation
    end
  end

  defp grant_operations(data, context, claim) do
    [
      fn -> OAuthGrantStore.claim(context, data.tenant, data.connection.id, 1, 1) end,
      fn ->
        OAuthGrantStore.complete(context, data.tenant, data.connection.id, 1, claim, %{
          "access_token" => "replacement"
        })
      end,
      fn -> OAuthGrantStore.fail(context, data.tenant, data.connection.id, 1, claim) end
    ]
  end

  test "catalog refresh preserves a rotated grant envelope and revision", data do
    {:ok, claim} = OAuthGrantStore.claim(data.context, data.tenant, data.connection.id, 1, 1)

    assert :ok =
             OAuthGrantStore.complete(
               data.context,
               data.tenant,
               data.connection.id,
               1,
               claim.id,
               %{"access_token" => "new-access", "refresh_token" => "rotated-refresh"}
             )

    before = Repo.get_by!(Vxpipe.Persistence.Schema.MCPConnection, public_id: data.connection.id)

    assert {:ok, refreshed} =
             ConnectionStore.refresh_catalog(
               Keyword.delete(data.context, :keyring),
               data.tenant,
               data.connection.id,
               1,
               %{
                 server_name: "Renamed tools",
                 catalog: [%{"name" => "new_tool", "inputSchema" => %{"type" => "object"}}]
               }
             )

    after_refresh =
      Repo.get_by!(Vxpipe.Persistence.Schema.MCPConnection, public_id: data.connection.id)

    assert refreshed.generation == 1
    assert after_refresh.encrypted_payload == before.encrypted_payload

    assert {:ok, resolved} =
             ConnectionStore.resolve(data.context, data.tenant, data.connection.id)

    assert resolved.secrets["refresh_token"] == "rotated-refresh"
    assert resolved.secrets["grant_revision"] == 2
  end

  test "one durable refresh claim rotates credentials without changing configuration generation",
       data do
    assert {:ok, claim} =
             OAuthGrantStore.claim(data.context, data.tenant, data.connection.id, 1, 1)

    assert claim.secrets["refresh_token"] == "old-refresh"
    refute inspect(claim) =~ "old-refresh"

    assert {:error, :oauth_refresh_in_progress} =
             OAuthGrantStore.claim(data.context, data.tenant, data.connection.id, 1, 1)

    assert :ok =
             OAuthGrantStore.complete(
               data.context,
               data.tenant,
               data.connection.id,
               1,
               claim.id,
               %{
                 "access_token" => "new-access",
                 "refresh_token" => "new-refresh",
                 "expires_at" => "2026-11-06T12:05:00Z"
               }
             )

    assert {:ok, resolved} =
             ConnectionStore.resolve(data.context, data.tenant, data.connection.id)

    assert resolved.connection.generation == 1
    assert resolved.secrets["grant_revision"] == 2
    assert resolved.secrets["refresh_token"] == "new-refresh"
    assert resolved.secrets["client_id"] == "client"
    assert resolved.secrets["client_secret_expires_at"] == 2_000_000_000

    assert {:error, :stale_oauth_grant} =
             OAuthGrantStore.claim(data.context, data.tenant, data.connection.id, 1, 1)

    assert {:error, :stale_oauth_refresh} =
             OAuthGrantStore.complete(
               data.context,
               data.tenant,
               data.connection.id,
               1,
               claim.id,
               %{"access_token" => "replayed"}
             )
  end

  test "token update cannot alter client identity and omitted refresh token retains current token",
       data do
    {:ok, claim} = OAuthGrantStore.claim(data.context, data.tenant, data.connection.id, 1, 1)

    assert {:error, :invalid_oauth_tokens} =
             OAuthGrantStore.complete(
               data.context,
               data.tenant,
               data.connection.id,
               1,
               claim.id,
               %{"access_token" => "new", "client_id" => "other"}
             )

    assert {:error, :invalid_oauth_tokens} =
             OAuthGrantStore.complete(
               data.context,
               data.tenant,
               data.connection.id,
               1,
               claim.id,
               %{"access_token" => "new", "client_secret_expires_at" => 0}
             )

    assert :ok =
             OAuthGrantStore.complete(
               data.context,
               data.tenant,
               data.connection.id,
               1,
               claim.id,
               %{"access_token" => "new"}
             )

    assert {:ok, resolved} =
             ConnectionStore.resolve(data.context, data.tenant, data.connection.id)

    assert resolved.secrets["refresh_token"] == "old-refresh"
    assert resolved.secrets["expires_at"] == nil
    assert resolved.secrets["scope"] == "tools:read"
    assert resolved.secrets["client_id"] == "client"
    assert resolved.secrets["client_secret_expires_at"] == 2_000_000_000
  end

  test "failed exchange permanently fences the claimed token until reconnect", data do
    {:ok, claim} = OAuthGrantStore.claim(data.context, data.tenant, data.connection.id, 1, 1)
    assert :ok = OAuthGrantStore.fail(data.context, data.tenant, data.connection.id, 1, claim.id)

    assert {:error, :oauth_reconnect_required} =
             OAuthGrantStore.claim(data.context, data.tenant, data.connection.id, 1, 1)

    assert {:error, :oauth_reconnect_required} =
             OAuthGrantStore.complete(
               data.context,
               data.tenant,
               data.connection.id,
               1,
               claim.id,
               %{"access_token" => "late"}
             )
  end

  test "OAuth reconnect fences an old refresh and leaves a fresh grant at the new generation",
       data do
    {:ok, claim} = OAuthGrantStore.claim(data.context, data.tenant, data.connection.id, 1, 1)

    assert {:ok, replaced} =
             ConnectionStore.replace(
               data.context,
               data.tenant,
               data.connection.id,
               1,
               data.connection,
               %{
                 "access_token" => "reconnected-access",
                 "refresh_token" => "reconnected-refresh",
                 "client_id" => "registered"
               }
             )

    assert replaced.id == data.connection.id
    assert replaced.generation == 2

    assert {:error, :oauth_connection_unavailable} =
             OAuthGrantStore.complete(
               data.context,
               data.tenant,
               data.connection.id,
               1,
               claim.id,
               %{"access_token" => "late-refresh"}
             )

    assert {:ok, resolved} =
             ConnectionStore.resolve(data.context, data.tenant, data.connection.id)

    assert resolved.secrets["access_token"] == "reconnected-access"

    assert {:ok, fresh_claim} =
             OAuthGrantStore.claim(data.context, data.tenant, data.connection.id, 2, 1)

    assert fresh_claim.secrets["refresh_token"] == "reconnected-refresh"
  end

  test "revocation fences a refresh that already holds old credentials", data do
    {:ok, claim} = OAuthGrantStore.claim(data.context, data.tenant, data.connection.id, 1, 1)
    {:ok, _} = ConnectionStore.revoke(data.context, data.tenant, data.connection.id, 1)

    assert {:error, :oauth_connection_unavailable} =
             OAuthGrantStore.complete(
               data.context,
               data.tenant,
               data.connection.id,
               1,
               claim.id,
               %{"access_token" => "resurrected"}
             )
  end

  test "expired ambiguous refresh cannot be reclaimed or completed", data do
    {:ok, claim} = OAuthGrantStore.claim(data.context, data.tenant, data.connection.id, 1, 1)
    expired = Keyword.put(data.context, :now, fn -> DateTime.add(@now, 30) end)

    assert {:error, :oauth_reconnect_required} =
             OAuthGrantStore.claim(expired, data.tenant, data.connection.id, 1, 1)

    assert {:error, :oauth_reconnect_required} =
             OAuthGrantStore.complete(expired, data.tenant, data.connection.id, 1, claim.id, %{
               "access_token" => "late"
             })
  end

  test "wrong-tenant grant operations cannot alter a live claim", data do
    {:ok, other, _} =
      Administration.bootstrap_tenant("Other grant tenant", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    {:ok, claim} = OAuthGrantStore.claim(data.context, data.tenant, data.connection.id, 1, 1)
    {:ok, before} = ConnectionStore.resolve(data.context, data.tenant, data.connection.id)

    for operation <- grant_operations(%{data | tenant: other.key}, data.context, claim.id) do
      assert {:error, :oauth_connection_unavailable} = operation.()
    end

    assert {:ok, after_attempts} =
             ConnectionStore.resolve(data.context, data.tenant, data.connection.id)

    assert after_attempts.secrets == before.secrets

    assert :ok =
             OAuthGrantStore.complete(
               data.context,
               data.tenant,
               data.connection.id,
               1,
               claim.id,
               %{"access_token" => "authorized"}
             )
  end

  test "invalid completion rolls back without consuming the refresh claim", data do
    {:ok, claim} = OAuthGrantStore.claim(data.context, data.tenant, data.connection.id, 1, 1)
    {:ok, before} = ConnectionStore.resolve(data.context, data.tenant, data.connection.id)

    for tokens <- [
          %{},
          %{"access_token" => String.duplicate("x", 32_769)},
          %{"access_token" => "new", "expires_at" => "invalid"},
          %{"access_token" => "new", "refresh_token" => nil}
        ] do
      assert {:error, :invalid_oauth_tokens} =
               OAuthGrantStore.complete(
                 data.context,
                 data.tenant,
                 data.connection.id,
                 1,
                 claim.id,
                 tokens
               )

      assert {:ok, unchanged} =
               ConnectionStore.resolve(data.context, data.tenant, data.connection.id)

      assert unchanged.secrets == before.secrets
    end

    assert :ok =
             OAuthGrantStore.complete(
               data.context,
               data.tenant,
               data.connection.id,
               1,
               claim.id,
               %{"access_token" => "valid"}
             )
  end

  test "credential re-encryption preserves a live refresh claim and completion uses the new key",
       data do
    {:ok, claim} = OAuthGrantStore.claim(data.context, data.tenant, data.connection.id, 1, 1)
    {:ok, old_key} = CredentialKeyring.fetch(Keyword.fetch!(data.context, :keyring), "key")
    new_key = :crypto.strong_rand_bytes(32)
    {:ok, both} = CredentialKeyring.new("new", %{"key" => old_key, "new" => new_key})
    {:ok, only_new} = CredentialKeyring.new("new", %{"new" => new_key})
    rotated = Keyword.put(data.context, :keyring, both)

    assert {:ok, %{processed: 1, remaining_by_key: remaining}} =
             ConnectionStore.reencrypt(rotated, 100)

    assert remaining == %{}
    current = Keyword.put(data.context, :keyring, only_new)
    assert {:ok, during} = ConnectionStore.resolve(current, data.tenant, data.connection.id)
    assert during.secrets["refresh_claim"]["id"] == claim.id

    assert :ok =
             OAuthGrantStore.complete(current, data.tenant, data.connection.id, 1, claim.id, %{
               "access_token" => "rotated"
             })

    assert {:ok, after_completion} =
             ConnectionStore.resolve(current, data.tenant, data.connection.id)

    assert after_completion.connection.generation == 1
    assert after_completion.secrets["grant_revision"] == 2
    assert after_completion.secrets["access_token"] == "rotated"
  end
end
