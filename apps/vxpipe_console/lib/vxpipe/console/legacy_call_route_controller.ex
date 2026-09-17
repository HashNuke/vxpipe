defmodule Vxpipe.Console.LegacyCallRouteController do
  @moduledoc false

  use Phoenix.Controller, formats: [:html]

  def index(conn, %{"tenant_key" => tenant_key}) do
    redirect_private(conn, "/admin/tenants/#{segment(tenant_key)}/calls")
  end

  def show(conn, %{"tenant_key" => tenant_key, "call_id" => call_id}) do
    redirect_private(
      conn,
      "/admin/tenants/#{segment(tenant_key)}/calls/#{segment(call_id)}"
    )
  end

  defp redirect_private(conn, destination) do
    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> redirect(to: destination)
  end

  defp segment(value), do: URI.encode(value, &URI.char_unreserved?/1)
end
