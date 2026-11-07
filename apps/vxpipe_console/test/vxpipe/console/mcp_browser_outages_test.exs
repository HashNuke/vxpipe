defmodule Vxpipe.Console.MCPBrowserOutagesTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test
  alias Vxpipe.Calls.MCPConnections

  alias Vxpipe.Console.Test.{
    FakeUserIdentity,
    MCPBrowserDirectoryProxy,
    MCPBrowserOutages,
    MCPManagementFixture
  }

  @tenant "AAAAAAAAAAAAAAAA"

  setup do
    original = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)

    calls =
      Keyword.merge(original,
        credential_repository: {MCPManagementFixture, self()},
        mcp_connection_repository: {MCPManagementFixture, self()}
      )

    Application.put_env(:vxpipe_calls, Vxpipe.Calls, calls)
    on_exit(fn -> Application.put_env(:vxpipe_calls, Vxpipe.Calls, original) end)
    Req.Test.verify_on_exit!()
    %{calls: calls}
  end

  test "directory startup faults leave local status usable and recover through the real upstream" do
    state =
      start_supervised!(
        {MCPBrowserOutages, upstream: "http://127.0.0.1:41872", directory_mode: "unavailable"}
      )

    assert {:ok, []} = MCPConnections.list(FakeUserIdentity.principal(), @tenant)
    assert proxy(state).status == 503
    assert :ok = MCPBrowserOutages.directory(state, "rate_limited")
    limited = proxy(state)
    assert limited.status == 429
    assert get_resp_header(limited, "retry-after") == ["60"]
    assert MCPBrowserOutages.snapshot(state).forwarded == 0

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/v1/integrations"
      assert conn.query_string == "category=calendar&limit=20"
      assert get_req_header(conn, "x-vxpipe-version") == ["0.1.0"]
      assert get_req_header(conn, "if-none-match") == ["previous"]
      assert get_req_header(conn, "authorization") == []
      assert get_req_header(conn, "cookie") == []

      conn
      |> put_resp_header("etag", "current")
      |> put_resp_content_type("application/json")
      |> send_resp(200, "{\"from\":\"actual-upstream\"}")
    end)

    assert :ok = MCPBrowserOutages.directory(state, "healthy")
    healthy = proxy(state)
    assert healthy.status == 200
    assert healthy.resp_body == "{\"from\":\"actual-upstream\"}"
    assert get_resp_header(healthy, "etag") == ["current"]

    assert MCPBrowserOutages.snapshot(state) == %{
             directory_mode: "healthy",
             local_status: "healthy",
             requests: 3,
             forwarded: 1
           }
  end

  test "local-status startup fault leaves upstream usable and restores exactly the saved port",
       c do
    state =
      start_supervised!(
        {MCPBrowserOutages,
         upstream: "https://directory.example.test", local_status: "unavailable"}
      )

    assert {:error, :repository_unavailable} =
             MCPConnections.list(FakeUserIdentity.principal(), @tenant)

    Req.Test.expect(__MODULE__, fn conn -> send_resp(conn, 304, "") end)
    assert proxy(state).status == 304
    assert MCPBrowserOutages.snapshot(state).directory_mode == "healthy"
    assert :ok = MCPBrowserOutages.local_status(state, "healthy")
    assert Map.new(Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)) == Map.new(c.calls)
    assert {:ok, []} = MCPConnections.list(FakeUserIdentity.principal(), @tenant)
  end

  test "invalid startup options and control values leave configured ports unchanged", c do
    for options <- [
          [directory_mode: "typo"],
          [local_status: "typo"],
          [upstream: "http://public.example.test"],
          [upstream: "https://private@example.test"],
          [upstream: "https://example.test/path?token=private"]
        ] do
      options = Keyword.merge([upstream: "http://127.0.0.1:41872"], options)
      assert {:error, :invalid_browser_outage_options} = MCPBrowserOutages.start_link(options)
      assert Map.new(Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)) == Map.new(c.calls)
    end

    state = start_supervised!({MCPBrowserOutages, upstream: "http://127.0.0.1:41872"})
    assert {:error, :invalid_browser_outage_mode} = MCPBrowserOutages.directory(state, "typo")
    assert {:error, :invalid_browser_outage_mode} = MCPBrowserOutages.local_status(state, "typo")
    assert Map.new(Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)) == Map.new(c.calls)
  end

  test "proxy rejects non-catalog requests and bounds upstream responses" do
    state = start_supervised!({MCPBrowserOutages, upstream: "http://127.0.0.1:41872"})
    options = %{state: state, http_options: [plug: {Req.Test, __MODULE__}]}

    assert conn(:post, "/v1/integrations")
           |> MCPBrowserDirectoryProxy.call(options)
           |> Map.fetch!(:status) == 404

    assert conn(:get, "/admin") |> MCPBrowserDirectoryProxy.call(options) |> Map.fetch!(:status) ==
             404

    assert MCPBrowserOutages.snapshot(state).forwarded == 0

    Req.Test.expect(__MODULE__, fn conn ->
      send_resp(conn, 200, String.duplicate("x", 1_048_577))
    end)

    assert proxy(state).status == 502
  end

  test "manual launcher refuses non-development evaluation before changing application ports",
       c do
    launcher = Path.expand("../../../../../test/browser/integrations.exs", __DIR__)

    assert_raise RuntimeError, ~r/isolated.*VXPIPE_BROWSER_ACCEPTANCE=1/, fn ->
      Code.eval_file(launcher)
    end

    assert Map.new(Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)) == Map.new(c.calls)
  end

  defp proxy(state) do
    conn(:get, "/v1/integrations?category=calendar&limit=20")
    |> put_req_header("x-vxpipe-version", "0.1.0")
    |> put_req_header("if-none-match", "previous")
    |> put_req_header("authorization", "synthetic-private")
    |> put_req_header("cookie", "synthetic-private")
    |> MCPBrowserDirectoryProxy.call(%{
      state: state,
      http_options: [plug: {Req.Test, __MODULE__}]
    })
  end
end
