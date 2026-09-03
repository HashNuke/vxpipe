defmodule Vxpipe.Gateway.HTTP.Router do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  alias Vxpipe.Gateway.HTTP.{RTVI, Rooms}

  @impl true
  def init(options) do
    %{
      rooms: options |> Keyword.get(:room_creation, []) |> Rooms.init(),
      rtvi: options |> Keyword.get(:webrtc, []) |> RTVI.init()
    }
  end

  @impl true
  def call(%Plug.Conn{method: "GET", path_info: ["healthz"]} = conn, _options) do
    send_resp(conn, 200, "ok")
  end

  def call(%Plug.Conn{method: "POST", path_info: ["api", "rooms"]} = conn, options) do
    Rooms.create(conn, options.rooms)
  end

  def call(
        %Plug.Conn{method: "POST", path_info: ["api", "rooms", room_id, "sessions"]} = conn,
        options
      ) do
    Rooms.create_session(conn, options.rooms, room_id)
  end

  def call(%Plug.Conn{method: "POST", path_info: ["api", "rtvi", "offer"]} = conn, options) do
    RTVI.offer(conn, options.rtvi)
  end

  def call(%Plug.Conn{method: "PATCH", path_info: ["api", "rtvi", "offer"]} = conn, options) do
    RTVI.add_ice_candidates(conn, options.rtvi)
  end

  def call(conn, _options), do: send_resp(conn, 404, "not found")
end
