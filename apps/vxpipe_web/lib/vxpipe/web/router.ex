defmodule Vxpipe.Web.Router do
  @moduledoc """
  Framework-neutral HTTP entry point for health checks, webhooks, and
  WebSocket upgrades.

  Provider adapter applications will mount their webhook and media ingress
  plugs here. Live call-audio subscribers will be upgraded through
  `WebSockAdapter` without requiring Phoenix.
  """

  use Plug.Router

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:vxpipe, :web])
  plug(:match)
  plug(:dispatch)

  get "/health" do
    send_resp(conn, 200, "ok")
  end

  get "/ready" do
    if Process.whereis(Vxpipe.RoomsSupervisor) do
      send_resp(conn, 200, "ready")
    else
      send_resp(conn, 503, "not ready")
    end
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
