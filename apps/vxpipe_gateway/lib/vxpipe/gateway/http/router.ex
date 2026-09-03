defmodule Vxpipe.Gateway.HTTP.Router do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  alias Vxpipe.Gateway.HTTP.Rooms

  @impl true
  def init(options) do
    %{room_creation: options |> Keyword.get(:room_creation, []) |> Rooms.init()}
  end

  @impl true
  def call(%Plug.Conn{method: "GET", path_info: ["healthz"]} = conn, _options) do
    send_resp(conn, 200, "ok")
  end

  def call(%Plug.Conn{method: "POST", path_info: ["api", "rooms"]} = conn, options) do
    Rooms.create(conn, options.room_creation)
  end

  def call(conn, _options), do: send_resp(conn, 404, "not found")
end
