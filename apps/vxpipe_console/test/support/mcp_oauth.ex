defmodule Vxpipe.Console.Test.MCPOAuth do
  @moduledoc false
  alias Vxpipe.Calls
  alias Vxpipe.Identity.{Sessions, Tokens}
  alias Vxpipe.Persistence.{IdentityRoleStore, IdentitySessionStore, IdentityUserStore, Repo}
  alias Vxpipe.Persistence.OAuth.Store

  alias Vxpipe.Persistence.Schema.{
    AuthenticationInstallation,
    IdentityMembership,
    IdentityRole,
    IdentityRolePermission,
    IdentityUser,
    Tenant
  }

  @resource "https://localhost/mcp"
  @verifier String.duplicate("a", 43)

  def resource, do: @resource

  def configure do
    previous = Application.fetch_env(:vxpipe_identity, :oauth_store)
    Application.put_env(:vxpipe_identity, :oauth_store, Store)

    ExUnit.Callbacks.on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:vxpipe_identity, :oauth_store, value)
        :error -> Application.delete_env(:vxpipe_identity, :oauth_store)
      end
    end)
  end

  def equivalent_to_api_key(secret) do
    {:ok, key_actor} = Calls.authenticate_api_key(secret)
    {role, tenant} = role_for(key_actor)
    id = Ecto.UUID.generate()

    user =
      Repo.insert!(
        IdentityUser.changeset(%IdentityUser{}, %{
          public_id: id,
          email: "mcp-#{id}@example.test",
          normalized_email: "mcp-#{id}@example.test",
          password_hash: "synthetic-mcp-oauth-hash",
          role_id: role.id
        })
      )

    if tenant do
      Repo.insert!(
        IdentityMembership.changeset(%IdentityMembership{}, %{
          user_id: user.id,
          tenant_id: tenant.id,
          access_level: "read_write"
        })
      )
    end

    installation = Repo.get!(AuthenticationInstallation, "default")

    if is_nil(installation.setup_completed_at) do
      installation
      |> Ecto.Changeset.change(
        setup_completed_at: DateTime.utc_now(),
        initial_superadmin_user_id: user.id
      )
      |> Repo.update!()
    end

    {:ok, %{token: raw, digest: digest}} = Tokens.generate()

    {:ok, _} =
      IdentitySessionStore.create(%{
        public_id: Ecto.UUID.generate(),
        user_public_id: id,
        digest: digest,
        expires_at: DateTime.add(DateTime.utc_now(), 3600)
      })

    {:ok, principal} =
      Sessions.authenticate(
        %{users: IdentityUserStore, roles: IdentityRoleStore, sessions: IdentitySessionStore},
        raw
      )

    issue(principal)
  end

  def issue(principal) do
    {:ok, client} =
      Store.register_client(%{
        "client_name" => "MCP acceptance",
        "redirect_uris" => ["https://client.example.test/callback"]
      })

    params = %{
      "response_type" => "code",
      "client_id" => client.client_id,
      "redirect_uri" => "https://client.example.test/callback",
      "resource" => @resource,
      "scope" => "mcp",
      "code_challenge_method" => "S256",
      "code_challenge" => :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false)
    }

    {:ok, snapshot} = Store.consent_snapshot(principal)
    {:ok, issued} = Store.issue_code(principal, params, @resource, snapshot)

    {:ok, tokens} =
      Store.exchange(
        %{
          "grant_type" => "authorization_code",
          "client_id" => client.client_id,
          "redirect_uri" => params["redirect_uri"],
          "resource" => @resource,
          "code" => issued.code,
          "code_verifier" => @verifier
        },
        @resource
      )

    Map.merge(tokens, %{
      client_id: client.client_id,
      grant_id: issued.grant_id,
      principal: principal
    })
  end

  def refresh(tokens) do
    Store.exchange(
      %{
        "grant_type" => "refresh_token",
        "client_id" => tokens.client_id,
        "refresh_token" => tokens.refresh_token
      },
      @resource
    )
  end

  def revoke(tokens),
    do:
      Store.revoke(%{"client_id" => tokens.client_id, "token" => tokens.access_token}, @resource)

  defp role_for(%Calls.InstallationOperator{}),
    do: {Repo.get_by!(IdentityRole, slug: "superadmin"), nil}

  defp role_for(%Calls.Principal{tenant_key: tenant_key, scopes: scopes}) do
    id = Ecto.UUID.generate()

    role =
      Repo.insert!(
        IdentityRole.ordinary_changeset(%IdentityRole{}, %{
          public_id: id,
          slug: "mcp-" <> id,
          name: "MCP fixture"
        })
      )

    grants =
      if(MapSet.member?(scopes, :calls), do: ~w(calls.read calls.write), else: []) ++
        if MapSet.member?(scopes, :admin), do: ~w(call_specs.read call_specs.write), else: []

    for grant <- grants do
      Repo.insert_all(IdentityRolePermission, [
        %{role_id: role.id, permission_key: grant, scope: "assigned_tenants"}
      ])
    end

    {role, Repo.get_by!(Tenant, key: tenant_key)}
  end
end
