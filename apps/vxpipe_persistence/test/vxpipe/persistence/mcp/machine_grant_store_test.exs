defmodule Vxpipe.Persistence.MCP.MachineGrantStoreTest do
  use Vxpipe.Persistence.DataCase, async: false
  alias Vxpipe.Calls.Administration
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, Repo}
  alias Vxpipe.Persistence.MCP.{ConnectionStore, OAuthGrantStore}
  @now ~U[2026-11-06 12:00:00.000000Z]

  test "machine token renewal uses a fenced claim without requiring or accepting refresh tokens" do
    {:ok, tenant, _} =
      Administration.bootstrap_tenant("Machine tenant", [:admin],
        credential_repository: {CredentialStore, Repo}
      )

    {:ok, keyring} = CredentialKeyring.new("key", %{"key" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keyring, now: fn -> @now end]

    secrets = %{
      "registration_method" => "own_client",
      "grant_type" => "client_credentials",
      "auth_method" => "client_secret_post",
      "client_id" => "registered",
      "client_secret" => "private-secret",
      "access_token" => "old-access"
    }

    {:ok, connection} =
      ConnectionStore.create(
        context,
        tenant.key,
        %{
          endpoint: "https://mcp.test/mcp",
          endpoint_identity: "https://mcp.test/mcp",
          server_name: "Tools",
          auth_method: "oauth",
          catalog: []
        },
        secrets
      )

    assert {:ok, claim} = OAuthGrantStore.claim(context, tenant.key, connection.id, 1, 1)
    refute Map.has_key?(claim.secrets, "refresh_token")

    assert {:error, :oauth_refresh_in_progress} =
             OAuthGrantStore.claim(context, tenant.key, connection.id, 1, 1)

    assert {:error, :invalid_oauth_tokens} =
             OAuthGrantStore.complete(context, tenant.key, connection.id, 1, claim.id, %{
               "access_token" => "new-access",
               "refresh_token" => "unexpected"
             })

    assert :ok =
             OAuthGrantStore.complete(context, tenant.key, connection.id, 1, claim.id, %{
               "access_token" => "new-access",
               "expires_at" => "2026-11-06T12:05:00Z"
             })

    assert {:ok, saved} = ConnectionStore.resolve(context, tenant.key, connection.id)
    assert saved.connection.generation == 1
    assert saved.secrets["grant_revision"] == 2
    assert saved.secrets["access_token"] == "new-access"
    assert saved.secrets["client_secret"] == "private-secret"
    assert saved.secrets["grant_type"] == "client_credentials"
    refute Map.has_key?(saved.secrets, "refresh_token")

    assert {:error, :stale_oauth_grant} =
             OAuthGrantStore.claim(context, tenant.key, connection.id, 1, 1)

    assert {:ok, next} = OAuthGrantStore.claim(context, tenant.key, connection.id, 1, 2)
    assert :ok = OAuthGrantStore.fail(context, tenant.key, connection.id, 1, next.id)

    assert {:error, :oauth_reconnect_required} =
             OAuthGrantStore.claim(context, tenant.key, connection.id, 1, 2)
  end
end
