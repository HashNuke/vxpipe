defmodule Vxpipe.Console.AdminSessionController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  def show(conn, _params) do
    grant = conn.assigns.installation_operator

    json(conn, %{
      operator: true,
      expires_at: grant.expires_at_unix |> DateTime.from_unix!() |> DateTime.to_iso8601()
    })
  end
end
