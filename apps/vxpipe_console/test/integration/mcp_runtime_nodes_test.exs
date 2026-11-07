defmodule Vxpipe.Console.MCPRuntimeNodesTest do
  use Vxpipe.Console.Test.MCPRuntimeNodeCase, async: false

  for grant <- ["authorization_code", "client_credentials"] do
    @tag grant: grant
    test "#{grant} rotation reaches POST, SSE reconnect and session DELETE on another node",
         data do
      stream = open(data)
      assert :ok = rpc(data.second, :refresh, [data.tenant, data.id, 1])
      assert_receive {:node_token_response, _, 200}, 5_000
      assert tokens(data) == 1
      assert {:ok, saved} = saved(data)
      token = "Bearer " <> saved.secrets["access_token"]
      assert saved.secrets["grant_revision"] == 2
      assert saved.secrets["grant_type"] == data.grant

      if data.grant == "client_credentials",
        do: refute(Map.has_key?(saved.secrets, "refresh_token"))

      assert {:ok, _} = rpc(data.first, :tool)
      assert_receive {:node_mcp_request, "POST", [^token], ["node-workspace"]}, 5_000
      assert_receive {:node_rpc, "tools/call"}, 5_000
      send(stream, :close_stream)
      assert_receive {:node_mcp_request, "GET", [^token], ["node-workspace"]}, 5_000
      assert_receive {:node_sse_stream, resumed, ["node-event"]}, 5_000
      assert {:ok, _} = rpc(data.first, :tool)
      assert_receive {:node_mcp_request, "POST", [^token], ["node-workspace"]}, 5_000
      assert_receive {:node_rpc, "tools/call"}, 5_000
      refute_received {:node_rpc, "initialize"}
      assert :ok = rpc(data.second, :refresh, [data.tenant, data.id, 2])
      assert_receive {:node_token_response, _, 200}, 5_000
      assert {:ok, current} = saved(data)
      assert current.secrets["grant_revision"] == 3
      assert current.secrets["grant_type"] == data.grant

      if data.grant == "client_credentials",
        do: refute(Map.has_key?(current.secrets, "refresh_token"))

      assert tokens(data) == 2
      cleanup_token = "Bearer " <> current.secrets["access_token"]
      refute cleanup_token == token
      assert :closed = rpc(data.first, :close)
      assert_receive {:node_mcp_request, "DELETE", [^cleanup_token], ["node-workspace"]}, 5_000
      send(resumed, :close_stream)
    end

    @tag grant: grant
    test "#{grant} revocation blocks POST, SSE reconnect and session DELETE on another node",
         data do
      stream = open(data)

      assert {:ok, %{status: "revoked"}} =
               rpc(data.second, :revoke, [data.context, data.tenant, data.id])

      assert {:error, _} = rpc(data.first, :tool)
      send(stream, :close_stream)
      assert :down = rpc(data.first, :await_stream_down)
      assert :closed = rpc(data.first, :close)
      refute_received {:node_mcp_request, _, _, _}
      refute_received {:node_rpc, "tools/call"}
      assert tokens(data) == 0
    end
  end

  test "revocation fences a real token response held on another node", data do
    hold(data, true)
    async(:renewed, fn -> rpc(data.first, :refresh, [data.tenant, data.id, 1]) end)
    assert_receive {:node_token_response, request, 200}, 5_000

    assert {:ok, %{status: "revoked"}} =
             rpc(data.second, :revoke, [data.context, data.tenant, data.id])

    send(request, :release_token)
    assert_receive {:renewed, {:error, :oauth_reconnect_required}}, 5_000
    assert {:error, :mcp_connection_revoked} = saved(data)
    assert tokens(data) == 1
  end

  test "a held renewal prevents duplicate redemption without blocking another tenant", data do
    hold(data, true)
    async(:renewed, fn -> rpc(data.first, :refresh, [data.tenant, data.id, 1]) end)
    assert_receive {:node_token_response, request, 200}, 5_000

    assert {:error, :oauth_refresh_in_progress} =
             rpc(data.second, :refresh, [data.tenant, data.id, 1])

    assert tokens(data) == 1
    hold(data, false)
    assert :ok = rpc(data.second, :refresh, [data.other_tenant, data.other_id, 1])
    assert_receive {:node_token_response, _, 200}, 5_000
    send(request, :release_token)
    assert_receive {:renewed, :ok}, 5_000
    assert tokens(data) == 2
  end

  test "a node crash after token redemption cannot cause a second exchange", data do
    assert {:ok, before} = saved(data)
    hold(data, true)
    async(:renewed, fn -> rpc(data.first, :refresh, [data.tenant, data.id, 1]) end)
    assert_receive {:node_token_response, request, 200}, 5_000
    monitor = Process.monitor(data.first)
    :peer.cast(data.first, :erlang, :halt, [137])
    assert_receive {:DOWN, ^monitor, :process, _, _}, 5_000
    assert_receive {:renewed, {:error, :node_stopped}}, 5_000
    send(request, :release_token)

    assert {:error, :oauth_refresh_in_progress} =
             rpc(data.second, :refresh, [data.tenant, data.id, 1])

    assert {:ok, held} = saved(data)
    assert Map.delete(held.secrets, "refresh_claim") == before.secrets
    deadline = DateTime.from_unix!(held.secrets["refresh_claim"]["deadline"])

    assert {:error, :oauth_reconnect_required} =
             rpc(data.second, :resolve, [data.tenant, data.id, deadline])

    assert tokens(data) == 1
  end
end
