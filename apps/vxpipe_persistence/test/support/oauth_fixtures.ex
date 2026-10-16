defmodule Vxpipe.Persistence.OAuthFixtures do
  @moduledoc false
  alias Vxpipe.Identity.{Sessions, Tokens}
  alias Vxpipe.Persistence.{IdentityRoleStore, IdentitySessionStore, IdentityUserStore, Repo}
  alias Vxpipe.Persistence.Schema.{AuthenticationInstallation, IdentityRole, IdentityUser}

  def browser_user do
    id = Ecto.UUID.generate()
    role = Repo.get_by!(IdentityRole, slug: "superadmin")

    user =
      Repo.insert!(
        IdentityUser.changeset(%IdentityUser{}, %{
          public_id: id,
          email: "oauth-#{id}@example.test",
          normalized_email: "oauth-#{id}@example.test",
          password_hash: "synthetic-oauth-hash",
          role_id: role.id
        })
      )

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

    %{user: user, principal: principal}
  end

  def registration do
    %{"client_name" => "Local OAuth test", "redirect_uris" => ["http://127.0.0.1:43210/callback"]}
  end

  def resource, do: "https://vxpipe.example.test/mcp"
  def verifier, do: String.duplicate("a", 43)

  def authorization(client_id) do
    %{
      "response_type" => "code",
      "client_id" => client_id,
      "redirect_uri" => "http://127.0.0.1:43210/callback",
      "scope" => "mcp",
      "state" => "test-state",
      "resource" => resource(),
      "code_challenge_method" => "S256",
      "code_challenge" => :crypto.hash(:sha256, verifier()) |> Base.url_encode64(padding: false)
    }
  end

  def exchange(client_id, code) do
    %{
      "grant_type" => "authorization_code",
      "client_id" => client_id,
      "redirect_uri" => "http://127.0.0.1:43210/callback",
      "code" => code,
      "code_verifier" => verifier(),
      "resource" => resource()
    }
  end

  def refresh(client_id, raw) do
    %{"grant_type" => "refresh_token", "client_id" => client_id, "refresh_token" => raw}
  end
end
