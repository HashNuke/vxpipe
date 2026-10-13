defmodule Vxpipe.Console.UserAuthController do
  @moduledoc "First-run setup, email login, and session termination."

  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Console.UserSession

  def status(conn, _params) do
    case backend().status() do
      {:ok, state} -> json(conn, %{status: state})
      {:error, _} -> error(conn, 503, "unavailable")
    end
  end

  def setup(conn, params) do
    address = conn.remote_ip |> :inet.ntoa() |> to_string()

    case backend().setup(
           Map.get(params, "email"),
           Map.get(params, "password"),
           Map.get(params, "password_confirmation"),
           Map.get(params, "proof"),
           address
         ) do
      {:ok, %{token: token}} -> started(conn, token)
      {:error, :already_complete} -> error(conn, 409, "already_complete")
      {:error, :already_completed} -> error(conn, 409, "already_complete")
      {:error, :proof_required} -> error(conn, 403, "proof_required")
      {:error, :invalid_proof} -> error(conn, 403, "invalid_proof")
      {:error, :rate_limited} -> error(conn, 429, "rate_limited")
      {:error, :unavailable} -> error(conn, 503, "unavailable")
      {:error, _} -> error(conn, 422, "invalid_setup")
    end
  end

  def login(conn, params) do
    address = conn.remote_ip |> :inet.ntoa() |> to_string()

    case backend().login(Map.get(params, "email"), Map.get(params, "password"), address) do
      {:ok, %{token: token}} -> started(conn, token)
      {:error, :rate_limited} -> error(conn, 429, "rate_limited")
      {:error, :unavailable} -> error(conn, 503, "unavailable")
      {:error, _} -> error(conn, 401, "invalid_credentials")
    end
  end

  def recover(conn, params) do
    address = conn.remote_ip |> :inet.ntoa() |> to_string()

    case backend().recover(
           Map.get(params, "proof"),
           Map.get(params, "email"),
           Map.get(params, "password"),
           Map.get(params, "password_confirmation"),
           address
         ) do
      {:ok, %{token: token}} ->
        started(conn, token)

      {:error, :rate_limited} ->
        error(conn, 429, "rate_limited")

      {:error, :not_complete} ->
        error(conn, 409, "not_complete")

      {:error, reason} when reason in [:invalid_proof, :expired_proof] ->
        error(conn, 403, "invalid_proof")

      {:error, :unavailable} ->
        error(conn, 503, "unavailable")

      {:error, _} ->
        error(conn, 422, "invalid_recovery")
    end
  end

  def logout(conn, _params) do
    result =
      case UserSession.token(conn) do
        token when is_binary(token) -> backend().logout(token)
        _ -> :ok
      end

    case result do
      :ok ->
        conn
        |> clear_session()
        |> configure_session(drop: true)
        |> redirect(to: "/auth/login")

      {:error, _reason} ->
        error(conn, 503, "unavailable")
    end
  end

  defp started(conn, token) do
    conn
    |> clear_session()
    |> configure_session(renew: true)
    |> UserSession.put(token)
    |> json(%{ok: true})
  end

  defp error(conn, status, code) do
    conn |> put_status(status) |> json(%{error: %{code: code}})
  end

  defp backend,
    do: Application.get_env(:vxpipe_console, :user_identity_backend, Vxpipe.Console.UserIdentity)
end
