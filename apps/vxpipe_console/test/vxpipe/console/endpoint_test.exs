defmodule Vxpipe.Console.EndpointTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  require Phoenix.ChannelTest

  alias Vxpipe.Console.DiagnosticsSocket
  alias Vxpipe.Gateway.HTTP

  @endpoint Vxpipe.Console.Endpoint

  test "serves the configured sample index and mounted gateway routes through one endpoint" do
    configure_sample_index(Path.expand("../../../priv/static/index.html", __DIR__))

    console_conn = get(build_conn(), "/")

    html = html_response(console_conn, 200)

    assert html =~ "Vxpipe RTVI Playground"
    assert html =~ ~s(src="/assets/app.js")
    assert html =~ ~s(href="/assets/app.css")
    refute html =~ "/src/main.tsx"
    assert Plug.Conn.get_resp_header(console_conn, "cache-control") == ["no-store"]

    gateway_conn = get(build_conn(), "/healthz")

    assert response(gateway_conn, 200) == "ok"
    assert Process.whereis(HTTP.Supervisor) == nil
    assert is_pid(Process.whereis(Vxpipe.Gateway.SessionSupervisor))
    assert is_pid(Process.whereis(Vxpipe.Gateway.WebRTC.ConnectionSupervisor))
  end

  test "reports unavailable sample assets without hiding the release error" do
    configure_sample_index(Path.join(System.tmp_dir!(), "missing-vxpipe-sample-index.html"))

    conn = get(build_conn(), "/")

    assert response(conn, 503) == "Vxpipe Console assets are not built"
  end

  test "reports unavailable sample assets when a compiled bundle is missing" do
    configure_sample_assets(
      Path.expand("../../../priv/static/index.html", __DIR__),
      [Path.join(System.tmp_dir!(), "missing-vxpipe-sample-app.js")]
    )

    conn = get(build_conn(), "/")

    assert response(conn, 503) == "Vxpipe Console assets are not built"
  end

  test "mounted gateway API paths do not fall through to console routing" do
    conn = get(build_conn(), "/api/not-a-route")

    assert response(conn, 404) == "not found"
  end

  test "diagnostics are disabled by default" do
    conn = get(build_conn(), "/diagnostics")

    assert response(conn, 404) == "not found"
  end

  test "diagnostic subscriptions fail closed unless diagnostics are enabled" do
    original = Application.fetch_env!(:vxpipe_console, :diagnostics)

    on_exit(fn -> Application.put_env(:vxpipe_console, :diagnostics, original) end)

    Application.put_env(:vxpipe_console, :diagnostics, Keyword.put(original, :enabled, false))

    assert :error = Phoenix.ChannelTest.connect(DiagnosticsSocket, %{})

    Application.put_env(:vxpipe_console, :diagnostics, Keyword.put(original, :enabled, true))

    assert {:ok, %Phoenix.Socket{}} = Phoenix.ChannelTest.connect(DiagnosticsSocket, %{})

    assert Enum.any?(@endpoint.__sockets__(), fn
             {"/diagnostics/live", DiagnosticsSocket, _options} -> true
             _socket -> false
           end)
  end

  test "enabled diagnostics require no authentication" do
    original = Application.fetch_env!(:vxpipe_console, :diagnostics)

    on_exit(fn -> Application.put_env(:vxpipe_console, :diagnostics, original) end)

    Application.put_env(:vxpipe_console, :diagnostics, enabled: true)

    diagnostics_conn = get(build_conn(), "/diagnostics")
    assert html_response(diagnostics_conn, 200) =~ "Vxpipe diagnostics"

    dashboard_conn = get(build_conn(), "/diagnostics/system")
    dashboard_path = redirected_to(dashboard_conn, 302)
    assert dashboard_path == "/diagnostics/system/home"

    dashboard_page = dashboard_conn |> recycle() |> get(dashboard_path)
    assert html_response(dashboard_page, 200) =~ "Phoenix LiveDashboard"

    %Plug.Conn{} = remote_conn = build_conn()
    remote_conn = %Plug.Conn{remote_conn | remote_ip: {203, 0, 113, 9}}
    remote_diagnostics_conn = get(remote_conn, "/diagnostics")

    assert html_response(remote_diagnostics_conn, 200) =~ "Vxpipe diagnostics"
  end

  defp configure_sample_index(index_path) do
    configure_sample_assets(index_path, [])
  end

  defp configure_sample_assets(index_path, required_paths) do
    original = Application.get_env(:vxpipe_console, :sample_assets, :not_configured)

    on_exit(fn ->
      case original do
        :not_configured -> Application.delete_env(:vxpipe_console, :sample_assets)
        settings -> Application.put_env(:vxpipe_console, :sample_assets, settings)
      end
    end)

    Application.put_env(:vxpipe_console, :sample_assets,
      index_path: index_path,
      required_paths: required_paths
    )
  end
end
