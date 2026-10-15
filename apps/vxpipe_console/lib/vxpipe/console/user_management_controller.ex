defmodule Vxpipe.Console.UserManagementController do
  @moduledoc "Authenticated account directory and administrative account actions."

  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Console.UserManagementPayload

  def index(conn, params) do
    with {:ok, page} <- page(Map.get(params, "page", "1")),
         {:ok, directory} <-
           backend().list_users(conn.assigns.user_principal, %{
             page: page,
             page_size: 25,
             search: Map.get(params, "q"),
             role_public_id: Map.get(params, "role")
           }) do
      json(conn, UserManagementPayload.user_page(directory, page, 25))
    else
      {:error, :invalid_page} ->
        error(conn, 422, "invalid_page")

      {:error, :unknown_role} ->
        error(conn, 422, "unknown_role")

      {:error, reason}
      when reason in [
             :page_out_of_range,
             :invalid_pagination,
             :invalid_search,
             :invalid_role_filter
           ] ->
        error(conn, 422, Atom.to_string(reason))

      {:error, :forbidden} ->
        error(conn, 403, "forbidden")

      {:error, _} ->
        error(conn, 503, "unavailable")
    end
  end

  def show(conn, %{"id" => id}) do
    case backend().get_user(conn.assigns.user_principal, id) do
      {:ok, user} -> json(conn, %{user: UserManagementPayload.user(user)})
      error_result -> account_error(conn, error_result)
    end
  end

  def create(conn, params) do
    with {:ok, memberships} <- memberships(Map.get(params, "memberships", [])),
         {:ok, user} <-
           backend().create_user(conn.assigns.user_principal, %{
             email: Map.get(params, "email"),
             password: Map.get(params, "password"),
             password_confirmation: Map.get(params, "password_confirmation"),
             role_public_id: Map.get(params, "role_id"),
             memberships: memberships
           }) do
      conn |> put_status(201) |> json(%{user: UserManagementPayload.user(user)})
    else
      error_result -> account_error(conn, error_result)
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, memberships} <- memberships(Map.get(params, "memberships", [])),
         {:ok, user} <-
           backend().update_user(conn.assigns.user_principal, id, %{
             email: Map.get(params, "email"),
             role_public_id: Map.get(params, "role_id"),
             disabled: Map.get(params, "enabled") == false,
             memberships: memberships
           }) do
      json(conn, %{user: UserManagementPayload.user(user)})
    else
      error_result -> account_error(conn, error_result)
    end
  end

  def reset_password(conn, %{"id" => id} = params) do
    case backend().reset_password(
           conn.assigns.user_principal,
           id,
           Map.get(params, "password"),
           Map.get(params, "password_confirmation")
         ) do
      :ok -> send_resp(conn, 204, "")
      error_result -> account_error(conn, error_result)
    end
  end

  defp memberships(entries) when is_list(entries) do
    Enum.reduce_while(entries, {:ok, %{}}, fn entry, {:ok, acc} ->
      case entry do
        %{"tenant_id" => tenant, "access" => access}
        when is_binary(tenant) and access in ["read", "read_write"] ->
          if Map.has_key?(acc, tenant),
            do: {:halt, {:error, :invalid_memberships}},
            else: {:cont, {:ok, Map.put(acc, tenant, access)}}

        _ ->
          {:halt, {:error, :invalid_memberships}}
      end
    end)
  end

  defp memberships(_), do: {:error, :invalid_memberships}

  defp account_error(conn, {:error, :forbidden}), do: error(conn, 403, "forbidden")
  defp account_error(conn, {:error, :not_found}), do: error(conn, 404, "not_found")
  defp account_error(conn, {:error, :unavailable}), do: error(conn, 503, "unavailable")
  defp account_error(conn, {:error, :stale}), do: error(conn, 409, "stale")
  defp account_error(conn, {:error, :last_superadmin}), do: error(conn, 409, "last_superadmin")
  defp account_error(conn, {:error, _}), do: error(conn, 422, "invalid_account")

  defp page(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp page(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> {:ok, number}
      _ -> {:error, :invalid_page}
    end
  end

  defp page(_), do: {:error, :invalid_page}

  defp error(conn, status, code), do: conn |> put_status(status) |> json(%{error: %{code: code}})

  defp backend,
    do: Application.get_env(:vxpipe_console, :user_identity_backend, Vxpipe.Console.UserIdentity)
end
