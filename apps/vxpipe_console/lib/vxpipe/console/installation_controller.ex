defmodule Vxpipe.Console.InstallationController do
  @moduledoc "Session-only Superadmin installation settings."
  use Phoenix.Controller, formats: [:html, :json]
  alias Vxpipe.Console.UserIdentity

  def page(conn, params) do
    case Vxpipe.Identity.InstallationSettings.authorize(conn.assigns.user_principal) do
      :ok -> Vxpipe.Console.AdminPageController.index(conn, params)
      _ -> send_resp(conn, 403, "Access unavailable")
    end
  end

  def show(conn, _params),
    do: respond(conn, UserIdentity.installation(conn.assigns.user_principal))

  def update(conn, params) do
    respond(
      conn,
      UserIdentity.update_installation(
        conn.assigns.user_principal,
        params["public_url"],
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
        :invalid_public_url -> {422, "invalid_public_url"}
        :invalid_revision -> {422, "invalid_revision"}
        _ -> {503, "unavailable"}
      end

    conn |> put_status(status) |> json(%{error: %{code: code}})
  end
end
