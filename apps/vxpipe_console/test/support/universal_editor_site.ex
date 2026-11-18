defmodule Vxpipe.Console.Test.UniversalEditorSite do
  @moduledoc "Loopback-only browser fixture using the real editor authoring controllers."
  @behaviour Plug

  import Plug.Conn
  alias Vxpipe.Console.AdminCallSpecAuthoringController, as: Controller

  def init(options), do: options

  def call(%{method: "GET", request_path: "/"} = conn, options) do
    html = """
    <!doctype html><html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Universal reply editor acceptance</title>
    <link rel="stylesheet" href="/assets/admin-ui.css">
    <link rel="stylesheet" href="/__editor/editor.css">
    <script type="module" src="/__editor/editor.js"></script></head>
    <body><div id="root"></div></body></html>
    """

    _ = options
    conn |> put_resp_content_type("text/html") |> send_resp(200, html)
  end

  def call(%{method: "GET", request_path: "/__editor/bootstrap"} = conn, options) do
    json(conn, options.bootstrap)
  end

  def call(%{method: "GET", path_info: ["__editor" | _]} = conn, options) do
    Plug.Static.call(conn, Plug.Static.init(at: "/__editor", from: options.assets))
  end

  def call(%{method: "GET", path_info: ["assets" | _]} = conn, _options) do
    Plug.Static.call(
      conn,
      Plug.Static.init(
        at: "/assets",
        from: Application.app_dir(:vxpipe_console, "priv/static/assets")
      )
    )
  end

  def call(conn, options) do
    conn =
      conn
      |> Plug.Parsers.call(Plug.Parsers.init(parsers: [:json], json_decoder: JSON))
      |> assign(:user_principal, options.authority)
      |> fetch_query_params()

    result =
      case {conn.method, conn.path_info} do
        {"POST", ["api", "tenants", tenant, "call-specs"]} when tenant == options.tenant ->
          Controller.create(conn, %{"tenant_key" => tenant})

        {"PUT", ["api", "tenants", tenant, "call-specs", id]} when tenant == options.tenant ->
          Controller.update(conn, %{"tenant_key" => tenant, "id" => id})

        {"POST", ["api", "tenants", tenant, "call-specs", id, "revisions", revision, "publish"]}
        when tenant == options.tenant ->
          Controller.publish(conn, %{"tenant_key" => tenant, "id" => id, "revision" => revision})

        {"GET", ["api", "tenants", tenant, "call-specs", id]} when tenant == options.tenant ->
          Controller.show(
            conn,
            Map.merge(conn.query_params, %{"tenant_key" => tenant, "id" => id})
          )

        _other ->
          send_resp(conn, 404, "not found")
      end

    if result.status in [200, 201] and conn.method in ["POST", "PUT"] do
      send(options.owner, {:universal_editor_write, result.status})
    end

    result
  end

  defp json(conn, value),
    do: conn |> put_resp_content_type("application/json") |> send_resp(200, JSON.encode!(value))
end
