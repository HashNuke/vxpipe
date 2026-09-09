defmodule Vxpipe.Console.PageController do
  use Phoenix.Controller, formats: [:html]

  def index(conn, _params) do
    case File.read(index_path()) do
      {:ok, html} ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.put_resp_header("cache-control", "no-store")
        |> Plug.Conn.send_resp(200, html)

      {:error, _reason} ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(503, "Vxpipe Console assets are not built")
    end
  end

  defp index_path do
    :vxpipe_console
    |> Application.get_env(:sample_assets, [])
    |> Keyword.get(:index_path)
    |> case do
      nil -> Application.app_dir(:vxpipe_console, "priv/static/index.html")
      path when is_binary(path) -> path
    end
  end
end
