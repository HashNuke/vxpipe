defmodule Vxpipe.Console.CallInspectionAssetController do
  @moduledoc false

  use Phoenix.Controller, formats: [:html]

  stylesheet_path = Path.expand("call_inspection_styles.css", __DIR__)
  phoenix_path = Application.app_dir(:phoenix, ["priv", "static", "phoenix.min.js"])

  live_view_path =
    Application.app_dir(:phoenix_live_view, ["priv", "static", "phoenix_live_view.min.js"])

  @external_resource stylesheet_path
  @external_resource phoenix_path
  @external_resource live_view_path

  @stylesheet File.read!(stylesheet_path)
  @stylesheet_hash Base.encode16(:crypto.hash(:sha256, @stylesheet), case: :lower)

  @javascript """
  #{File.read!(phoenix_path)}
  #{File.read!(live_view_path)}
  document.addEventListener("DOMContentLoaded",function(){
    var csrf=document.querySelector('meta[name="csrf-token"]').getAttribute("content");
    var socketPath=document.documentElement.getAttribute("phx-socket");
    var liveSocket=new LiveView.LiveSocket(socketPath,Phoenix.Socket,{params:{_csrf_token:csrf}});
    liveSocket.connect();
    window.liveSocket=liveSocket;
  });
  """
  @javascript_hash Base.encode16(:crypto.hash(:sha256, @javascript), case: :lower)

  @spec stylesheet_path() :: String.t()
  def stylesheet_path, do: "/calls/assets/styles/#{@stylesheet_hash}"

  @spec live_path() :: String.t()
  def live_path, do: "/calls/assets/live/#{@javascript_hash}"

  def show(conn, %{"kind" => "styles", "hash" => @stylesheet_hash}) do
    respond(conn, "text/css", @stylesheet)
  end

  def show(conn, %{"kind" => "live", "hash" => @javascript_hash}) do
    respond(conn, "text/javascript", @javascript)
  end

  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "not found")
    |> halt()
  end

  defp respond(conn, content_type, body) do
    conn
    |> put_resp_content_type(content_type)
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
    |> put_private(:plug_skip_csrf_protection, true)
    |> send_resp(200, body)
    |> halt()
  end
end
