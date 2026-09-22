defmodule Vxpipe.Console.PageController do
  use Phoenix.Controller, formats: [:html]

  def index(conn, _params) do
    settings = asset_settings()

    with true <- required_assets_available?(settings),
         {:ok, html} <- File.read(index_path(settings)) do
      html = String.replace(html, "__VXPIPE_CSRF_TOKEN__", Plug.CSRFProtection.get_csrf_token())

      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.put_resp_header("cache-control", "no-store")
      |> Plug.Conn.send_resp(200, html)
    else
      _unavailable ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(503, "Vxpipe Console assets are not built")
    end
  end

  defp asset_settings, do: Application.get_env(:vxpipe_console, :sample_assets, [])

  defp index_path(settings) do
    case Keyword.get(settings, :index_path) do
      nil -> Application.app_dir(:vxpipe_console, "priv/static/index.html")
      path when is_binary(path) -> path
    end
  end

  defp required_assets_available?(settings) do
    settings
    |> Keyword.get_lazy(:required_paths, fn ->
      [
        Application.app_dir(:vxpipe_console, "priv/static/assets/app.js"),
        Application.app_dir(:vxpipe_console, "priv/static/assets/app.css")
      ]
    end)
    |> Enum.all?(&File.regular?/1)
  end
end
