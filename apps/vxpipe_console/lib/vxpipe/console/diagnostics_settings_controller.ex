defmodule Vxpipe.Console.DiagnosticsSettingsController do
  @moduledoc "Session-only installation diagnostics settings operations."
  use Phoenix.Controller, formats: [:json]
  alias Vxpipe.Console.UserIdentity

  def show(conn, _params),
    do: respond(conn, UserIdentity.diagnostics_settings(conn.assigns.user_principal))

  def update(conn, params) do
    respond(
      conn,
      UserIdentity.update_diagnostics_settings(
        conn.assigns.user_principal,
        params["enabled"],
        params["revision"]
      )
    )
  end

  defp respond(conn, {:ok, settings}), do: json(conn, settings)

  defp respond(conn, {:error, reason}) do
    {status, code} =
      case reason do
        :forbidden -> {403, "forbidden"}
        :conflict -> {409, "conflict"}
        :invalid_enabled -> {422, "invalid_enabled"}
        :invalid_revision -> {422, "invalid_revision"}
        _ -> {503, "unavailable"}
      end

    conn |> put_status(status) |> json(%{error: %{code: code}})
  end
end
