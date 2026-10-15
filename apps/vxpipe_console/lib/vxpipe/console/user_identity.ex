defmodule Vxpipe.Console.UserIdentity do
  @moduledoc "Connects Console requests to the configured identity stores."

  alias Vxpipe.Identity.{Accounts, Bootstrap, Roles, Sessions}

  def status, do: with_dependencies(&Bootstrap.status/1)
  def issue_setup_proof, do: with_dependencies(&Bootstrap.issue_setup_proof/1)
  def issue_recovery_proof, do: with_dependencies(&Bootstrap.issue_recovery_proof/1)

  def recover(proof, email, password, confirmation, client_address),
    do:
      with_dependencies(
        &Bootstrap.recover_with_proof(&1, proof, email, password, confirmation, %{
          client_address: client_address
        })
      )

  def setup(email, password, confirmation, proof \\ nil, client_address \\ "local") do
    with_dependencies(fn deps ->
      if is_binary(proof) and proof != "" do
        Bootstrap.complete_with_proof(deps, proof, email, password, confirmation, %{
          client_address: client_address
        })
      else
        Bootstrap.complete_first_run(deps, email, password, confirmation, %{
          client_address: client_address
        })
      end
    end)
  end

  def login(email, password, client_address),
    do: with_dependencies(&Sessions.login(&1, email, password, client_address))

  def authenticate(token), do: with_dependencies(&Sessions.authenticate(&1, token))
  def logout(token), do: with_dependencies(&Sessions.logout(&1, token))

  def session_details(principal) do
    with_dependencies(fn deps ->
      with {:ok, user} <- deps.users.fetch_by_public_id(principal.user_public_id),
           {:ok, role} <- deps.roles.fetch(user.role_public_id) do
        {:ok, {Map.drop(user, [:password_hash]), role}}
      end
    end)
  end

  def list_users(actor, filters), do: with_dependencies(&Accounts.list_users(&1, actor, filters))
  def get_user(actor, id), do: with_dependencies(&Accounts.get_user(&1, actor, id))
  def create_user(actor, attrs), do: with_dependencies(&Accounts.create_user(&1, actor, attrs))

  def update_user(actor, id, attrs),
    do: with_dependencies(&Accounts.update_user(&1, actor, id, attrs))

  def reset_password(actor, id, password, confirmation),
    do: with_dependencies(&Accounts.reset_password(&1, actor, id, password, confirmation))

  def change_own_email(id, current_password, email),
    do: with_dependencies(&Accounts.change_own_email(&1, id, current_password, email))

  def change_own_password(id, current_password, password, confirmation),
    do:
      with_dependencies(
        &Accounts.change_own_password(&1, id, current_password, password, confirmation)
      )

  def update_account(principal, current_password, email, password, confirmation),
    do:
      with_dependencies(
        &Accounts.change_own_details(
          &1,
          principal.user_public_id,
          current_password,
          email,
          password,
          confirmation
        )
      )

  def list_roles(actor), do: with_dependencies(&Roles.list_roles(&1, actor))

  def get_role(actor, id) do
    case list_roles(actor) do
      {:ok, roles} ->
        case Enum.find(roles, &(&1.public_id == id)) do
          nil -> {:error, :not_found}
          role -> {:ok, role}
        end

      error ->
        error
    end
  end

  def list_role_options(actor), do: with_dependencies(&Roles.list_role_options(&1, actor))
  def affected_user_count(_actor, id), do: with_dependencies(&Roles.affected_user_count(&1, id))
  def create_role(actor, attrs), do: with_dependencies(&Roles.create_role(&1, actor, attrs))

  def update_role(actor, id, attrs),
    do: with_dependencies(&Roles.update_role(&1, actor, id, attrs))

  def delete_role(actor, id), do: with_dependencies(&Roles.delete_role(&1, actor, id))

  defp with_dependencies(callback) do
    with {:ok, dependencies} <- Vxpipe.Identity.dependencies() do
      callback.(dependencies)
    end
  end
end
