defmodule Vxpipe.Persistence.OAuth.Authority do
  @moduledoc "Locks and checks current user authority before OAuth issuance and credential use."
  import Ecto.Query
  alias Vxpipe.Identity.{Principal, OAuth.Delegation}
  alias Vxpipe.Persistence.{IdentityRecord, Repo}
  alias Vxpipe.Persistence.OAuth.{Grant, Transaction}

  alias Vxpipe.Persistence.Schema.{
    AuthenticationInstallation,
    IdentityRole,
    IdentitySession,
    IdentityUser
  }

  def browser(
        %Principal{
          credential_kind: :browser_session,
          oauth_grant_public_id: nil,
          session_public_id: session_id
        } = principal
      )
      when is_binary(session_id) do
    with :ok <- installation(),
         {:ok, user, role} <- user(principal.user_public_id, :public_id),
         %IdentitySession{} = session <-
           Repo.one(
             from(s in IdentitySession,
               where: s.public_id == ^session_id and s.user_id == ^user.id,
               lock: "FOR SHARE"
             ),
             Transaction.options()
           ),
         true <- is_nil(session.revoked_at) and Transaction.future?(session.expires_at),
         {:ok, current} <-
           Principal.for_session(user_map(user), role_map(role), %{public_id: session_id}) do
      {:ok,
       %{
         user: user_map(user),
         role: role_map(role),
         user_id: user.id,
         snapshot: current |> Delegation.snapshot() |> Map.put(:user_public_id, user.public_id)
       }}
    else
      _ -> {:error, :invalid_session}
    end
  end

  def browser(_), do: {:error, :invalid_session}

  def grant(grant_id, resource) do
    with :ok <- installation(),
         %Grant{} = hint <- Repo.get(Grant, grant_id, Transaction.options()),
         {:ok, user, role} <- user(hint.user_id, :id),
         %Grant{} = grant <-
           Repo.one(
             from(g in Grant, where: g.public_id == ^grant_id, lock: "FOR UPDATE"),
             Transaction.options()
           ),
         true <- active?(grant, user, role, resource) do
      {:ok, %{grant: grant, user: user_map(user), role: role_map(role)}}
    else
      _ -> {:error, :invalid_grant}
    end
  end

  def revoke(grant),
    do:
      Repo.update!(
        Ecto.Changeset.change(grant, revoked_at: Transaction.now()),
        Transaction.options()
      )

  def project_grant(grant) do
    Map.take(grant, [
      :public_id,
      :client_id,
      :authorization_version,
      :role_public_id,
      :role_revision,
      :authority,
      :resource,
      :expires_at,
      :revoked_at,
      :inserted_at
    ])
  end

  defp installation do
    case Repo.one(
           from(i in AuthenticationInstallation, where: i.key == "default", lock: "FOR SHARE"),
           Transaction.options()
         ) do
      %AuthenticationInstallation{setup_completed_at: %DateTime{}} -> :ok
      _ -> {:error, :unavailable}
    end
  end

  defp user(value, field) do
    with %IdentityUser{disabled_at: nil} = user <-
           Repo.one(
             from(u in IdentityUser, where: field(u, ^field) == ^value, lock: "FOR UPDATE"),
             Transaction.options()
           ),
         %IdentityRole{} = role <-
           Repo.one(
             from(r in IdentityRole, where: r.id == ^user.role_id, lock: "FOR SHARE"),
             Transaction.options()
           ) do
      {:ok, %{user | role: role}, role}
    else
      _ -> {:error, :invalid_grant}
    end
  end

  defp active?(grant, user, role, resource) do
    grant.resource == resource and is_nil(grant.revoked_at) and
      Transaction.future?(grant.expires_at) and
      grant.authorization_version == user.authorization_version and
      grant.role_public_id == role.public_id and
      grant.role_revision == role.revision
  end

  defp user_map(user),
    do:
      user
      |> IdentityRecord.user_port_map(IdentityRecord.load_memberships(user.id))
      |> Map.drop([:password_hash])

  defp role_map(role), do: IdentityRecord.role_port_map(role)
end
