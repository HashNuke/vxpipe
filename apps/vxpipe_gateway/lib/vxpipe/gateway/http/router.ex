defmodule Vxpipe.Gateway.HTTP.Router do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  alias Vxpipe.Gateway.HTTP.{CallAdmissions, RTVI, Rooms, TelnyxEvents}

  @impl true
  def init(options) do
    %{
      call_admission: options |> Keyword.get(:call_admission, []) |> CallAdmissions.init(),
      rooms: options |> Keyword.get(:room_creation, []) |> Rooms.init(),
      telephony: options |> Keyword.get(:telephony, []) |> TelnyxEvents.init(),
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
        %Plug.Conn{
          method: "POST",
          path_info: ["api", "telephony", "telnyx", ingress_key, "events"]
        } = conn,
        options
      ) do
    TelnyxEvents.handle(conn, options.telephony, ingress_key)
  end

  def call(
        %Plug.Conn{
          method: "POST",
          path_info: ["api", "tenants", tenant_key, "participants", participant_key, "calls"]
        } = conn,
        options
      ) do
    CallAdmissions.prepare(
      conn,
      options.call_admission,
      tenant_key,
      participant_key
    )
  end

  def call(
        %Plug.Conn{
          method: "POST",
          path_info: [
            "api",
            "tenants",
            tenant_key,
            "calls",
            call_id,
            "participants",
            participant_key,
            "sessions"
          ]
        } = conn,
        options
      ) do
    CallAdmissions.create_session(
      conn,
      options.call_admission,
      tenant_key,
      call_id,
      participant_key
    )
  end

  def call(
        %Plug.Conn{
          method: "POST",
          path_info: [
            "api",
            "tenants",
            tenant_key,
            "calls",
            call_id,
            "participants",
            participant_key,
            "join-tokens"
          ]
        } = conn,
        options
      ) do
    CallAdmissions.issue_token(
      conn,
      options.call_admission,
      tenant_key,
      call_id,
      participant_key
    )
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
