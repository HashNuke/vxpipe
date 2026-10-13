defmodule Vxpipe.Console.ConsoleLandingController do
  @moduledoc "Fresh-principal landing for the Console's root browser entry."
  use Phoenix.Controller, formats: [:html]

  alias Vxpipe.Console.{NavigationProjection, UserSession}

  def index(conn, _params) do
    backend =
      Application.get_env(:vxpipe_console, :user_identity_backend, Vxpipe.Console.UserIdentity)

    case UserSession.fetch(conn, backend: backend) do
      {:ok, principal} ->
        case NavigationProjection.build(principal, nil) do
          {:ok, navigation} ->
            saved_path = get_session(conn, "vxpipe_return_path")

            path =
              if Vxpipe.Console.RequireUser.allowed_path?(principal, saved_path),
                do: saved_path,
                else: navigation.landing_path

            conn |> delete_session("vxpipe_return_path") |> redirect(to: path)

          {:error, _} ->
            unavailable(conn)
        end

      {:error, reason} when reason in [:unavailable, :repository_unavailable] ->
        unavailable(conn)

      {:error, _} ->
        anonymous(UserSession.clear(conn), backend)
    end
  end

  defp anonymous(conn, backend) do
    case backend.status() do
      {:ok, :complete} ->
        redirect(conn, to: "/auth/login")

      {:ok, status} when status in [:pending_first_run, :pending_operator_proof] ->
        redirect(conn, to: "/auth/setup")

      _ ->
        unavailable(conn)
    end
  end

  defp unavailable(conn) do
    conn
    |> put_status(503)
    |> html("""
    <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Workspace unavailable · Vxpipe</title></head>
    <body><main><h1>Workspace unavailable</h1><p>We could not load your workspace. Please try again.</p><a href="/">Try again</a></main></body></html>
    """)
  end
end
