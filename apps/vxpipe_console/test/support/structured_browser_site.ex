defmodule Vxpipe.Console.Test.StructuredBrowserSite do
  @moduledoc "Local-only host for the production playground's structured-message acceptance."
  @behaviour Plug

  import Plug.Conn

  alias Vxpipe.Calls
  alias Vxpipe.Console.{Endpoint, SampleAdmissionJSON}

  @impl true
  def init(options), do: options

  @impl true
  def call(%{method: "GET", request_path: "/admin/samples/pipecat-console"} = conn, options) do
    html = """
    <!doctype html><html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="csrf-token" content="local-acceptance">
    <title>Structured agent acceptance</title><link rel="stylesheet" href="/__structured/site.css">
    <script type="module" src="/__structured/site.js"></script></head>
    <body><div id="root"></div></body></html>
    """

    _ = options
    conn |> put_resp_content_type("text/html") |> send_resp(200, html)
  end

  def call(%{method: "GET", path_info: ["__structured" | _]} = conn, options) do
    Plug.Static.call(conn, Plug.Static.init(at: "/__structured", from: options.assets))
  end

  def call(%{method: "POST", request_path: "/api/samples/calls"} = conn, options) do
    case Calls.prepare_call(options.principal, options.route, %{}, options.calls) do
      {:ok, call, token} ->
        send(options.owner, {:structured_browser_call, call})
        json(conn, 201, SampleAdmissionJSON.render(token))

      {:error, reason} ->
        send(options.owner, {:structured_browser_admission_failed, reason})
        json(conn, 503, %{error: "admission_failed"})
    end
  end

  def call(%{method: "POST", request_path: "/__structured/control"} = conn, options) do
    {:ok, body, conn} = read_body(conn, length: 65_536)
    {:ok, command} = JSON.decode(body)
    send(options.owner, {:structured_browser_control, command})
    json(conn, 200, %{accepted: true})
  end

  def call(conn, _options), do: Endpoint.call(conn, Endpoint.init([]))

  defp json(conn, status, value),
    do:
      conn |> put_resp_content_type("application/json") |> send_resp(status, JSON.encode!(value))
end
