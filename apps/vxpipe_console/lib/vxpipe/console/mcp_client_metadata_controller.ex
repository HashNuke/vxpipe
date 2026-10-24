defmodule Vxpipe.Console.MCPClientMetadataController do
  @moduledoc "Public CIMD document derived only from the saved Installation URL."
  use Phoenix.Controller, formats: [:json]

  def show(conn, _params) do
    conn = Plug.Conn.put_resp_header(conn, "cache-control", "no-store")

    with {:ok, origin} <- Vxpipe.Identity.InstallationSettings.public_url(),
         {:ok, metadata} <- Vxpipe.MCP.ClientMetadata.document(origin) do
      json(conn, metadata)
    else
      {:error, :invalid_public_url} -> unavailable(conn, "installation_url_required")
      _error -> unavailable(conn, "unavailable")
    end
  end

  defp unavailable(conn, code), do: conn |> put_status(503) |> json(%{error: %{code: code}})
end
