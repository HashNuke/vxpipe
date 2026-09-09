defmodule Vxpipe.Console.DiagnosticsAssetController do
  @moduledoc false

  use Phoenix.Controller, formats: [:html]

  phoenix_path = Application.app_dir(:phoenix, ["priv", "static", "phoenix.min.js"])

  live_view_path =
    Application.app_dir(:phoenix_live_view, ["priv", "static", "phoenix_live_view.min.js"])

  @external_resource phoenix_path
  @external_resource live_view_path

  @javascript """
  #{File.read!(phoenix_path)}
  #{File.read!(live_view_path)}
  document.addEventListener("DOMContentLoaded",function(){
    var csrf=document.querySelector('meta[name="csrf-token"]').getAttribute("content");
    var socketPath=document.documentElement.getAttribute("phx-socket");
    var hooks={MetricPulse:{updated:function(){
      if(!window.matchMedia("(prefers-reduced-motion: reduce)").matches){
        this.el.animate(
          [{backgroundColor:"var(--green-soft)"},{backgroundColor:"transparent"}],
          {duration:450,easing:"cubic-bezier(0.16, 1, 0.3, 1)"}
        );
      }
    }}};
    var liveSocket=new LiveView.LiveSocket(socketPath,Phoenix.Socket,{hooks:hooks,params:{_csrf_token:csrf}});
    liveSocket.connect();
    window.liveSocket=liveSocket;
  });
  """
  @hash Base.encode16(:crypto.hash(:sha256, @javascript), case: :lower)

  @spec path() :: String.t()
  def path, do: "/diagnostics/assets/live/#{@hash}"

  def show(conn, %{"hash" => @hash}) do
    conn
    |> Plug.Conn.put_resp_content_type("text/javascript")
    |> Plug.Conn.put_resp_header("cache-control", "public, max-age=31536000, immutable")
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
    |> Plug.Conn.send_resp(200, @javascript)
    |> Plug.Conn.halt()
  end

  def show(conn, _params) do
    conn
    |> Plug.Conn.put_resp_content_type("text/plain")
    |> Plug.Conn.send_resp(404, "not found")
    |> Plug.Conn.halt()
  end
end
