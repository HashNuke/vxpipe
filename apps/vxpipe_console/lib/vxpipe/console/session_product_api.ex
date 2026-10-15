defmodule Vxpipe.Console.SessionProductAPI do
  @moduledoc "Console-owned product routes that accept browser sessions only."

  @behaviour Plug

  alias Plug.Conn
  alias Vxpipe.Console.Router

  def route?(%Conn{} = conn) do
    case Phoenix.Router.route_info(Router, conn.method, conn.path_info, conn.host) do
      %{console_product_api: true} -> true
      _other -> false
    end
  end

  @impl true
  def init(options), do: options

  @impl true
  def call(conn, _options) do
    conn =
      conn
      |> Conn.put_resp_header("cache-control", "private, no-store")
      |> Conn.put_resp_header("referrer-policy", "no-referrer")

    case Conn.get_req_header(conn, "authorization") do
      [] ->
        conn

      _explicit_credentials ->
        conn
        |> Conn.put_resp_content_type("application/json")
        |> Conn.send_resp(401, JSON.encode!(%{error: %{code: "session_required"}}))
        |> Conn.halt()
    end
  end
end
