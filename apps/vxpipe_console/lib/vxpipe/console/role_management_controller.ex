defmodule Vxpipe.Console.RoleManagementController do
  @moduledoc "Protected role administration over the Identity role policy."

  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Console.UserManagementPayload

  def options(conn, _params) do
    case backend().list_role_options(conn.assigns.user_principal) do
      {:ok, roles} -> json(conn, %{roles: Enum.map(roles, &UserManagementPayload.role_option/1)})
      error_result -> role_error(conn, error_result)
    end
  end

  def index(conn, _params) do
    case backend().list_roles(conn.assigns.user_principal) do
      {:ok, roles} -> json(conn, %{roles: Enum.map(roles, &UserManagementPayload.role/1)})
      error_result -> role_error(conn, error_result)
    end
  end

  def show(conn, %{"id" => id}) do
    result =
      with {:ok, role} <- backend().get_role(conn.assigns.user_principal, id),
           {:ok, count} <- backend().affected_user_count(conn.assigns.user_principal, id) do
        {:ok, role, count}
      end

    case result do
      {:ok, role, count} ->
        json(conn, %{role: UserManagementPayload.role(role), affected_users: count})

      error_result ->
        role_error(conn, error_result)
    end
  end

  def create(conn, params) do
    attrs = %{
      slug: "custom-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower),
      name: Map.get(params, "name"),
      description: Map.get(params, "description", ""),
      grants: Map.get(params, "grants")
    }

    case backend().create_role(conn.assigns.user_principal, attrs) do
      {:ok, role} -> conn |> put_status(201) |> json(%{role: UserManagementPayload.role(role)})
      error_result -> role_error(conn, error_result)
    end
  end

  def update(conn, %{"id" => id} = params) do
    attrs = %{
      name: Map.get(params, "name"),
      description: Map.get(params, "description", ""),
      grants: Map.get(params, "grants"),
      expected_revision: Map.get(params, "expected_revision")
    }

    case backend().update_role(conn.assigns.user_principal, id, attrs) do
      {:ok, role} -> json(conn, %{role: UserManagementPayload.role(role)})
      error_result -> role_error(conn, error_result)
    end
  end

  def delete(conn, %{"id" => id}) do
    case backend().delete_role(conn.assigns.user_principal, id) do
      :ok -> send_resp(conn, 204, "")
      error_result -> role_error(conn, error_result)
    end
  end

  defp role_error(conn, {:error, :forbidden}), do: error(conn, 403, "forbidden")
  defp role_error(conn, {:error, :not_found}), do: error(conn, 404, "not_found")
  defp role_error(conn, {:error, :protected_role}), do: error(conn, 403, "protected_role")
  defp role_error(conn, {:error, :role_in_use}), do: error(conn, 409, "role_in_use")
  defp role_error(conn, {:error, :stale}), do: error(conn, 409, "stale")
  defp role_error(conn, {:error, :stale_revision}), do: error(conn, 409, "stale")
  defp role_error(conn, {:error, :unavailable}), do: error(conn, 503, "unavailable")
  defp role_error(conn, {:error, _}), do: error(conn, 422, "invalid_role")

  defp error(conn, status, code), do: conn |> put_status(status) |> json(%{error: %{code: code}})

  defp backend,
    do: Application.get_env(:vxpipe_console, :user_identity_backend, Vxpipe.Console.UserIdentity)
end
