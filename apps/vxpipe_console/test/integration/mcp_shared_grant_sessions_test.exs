defmodule Vxpipe.Console.Integration.MCPSharedGrantSessionsTest do
  use Vxpipe.Console.Test.MCPRuntimeNodeCase, async: false
  @moduletag :capture_log

  test "two live sessions share current renewal authority but have independent cleanup", data do
    Agent.update(data.state, &Map.put(&1, :expires_in, 3_600))

    streams =
      for peer <- [data.first, data.second] do
        assert :ok =
                 rpc(peer, :open, [data.tenant, data.id, data.base, [now: &MCPRuntimeNode.now/0]])

        assert_receive {:node_sse_stream, stream, []}, 5_000
        assert_receive {:node_rpc, "notifications/initialized"}, 5_000
        stream
      end

    assert length(Enum.uniq(streams)) == 2
    flush_protocol()
    assert {:ok, initial} = saved(data)
    {:ok, expiry, 0} = DateTime.from_iso8601(initial.secrets["expires_at"])

    for peer <- [data.first, data.second],
        do: assert(:ok == rpc(peer, :set_now, [DateTime.add(expiry, 1)]))

    assert {:ok, _} = rpc(data.first, :tool)
    assert_receive {:node_token_response, _, 200}, 5_000
    assert {:ok, current} = saved(data)
    token = "Bearer " <> current.secrets["access_token"]
    assert current.secrets["grant_revision"] == 2
    assert_receive {:node_mcp_request, "POST", [^token], ["node-workspace"]}, 5_000
    assert_receive {:node_rpc, "tools/call"}, 5_000
    assert {:ok, _} = rpc(data.second, :tool)
    assert_receive {:node_mcp_request, "POST", [^token], ["node-workspace"]}, 5_000
    assert_receive {:node_rpc, "tools/call"}, 5_000
    assert tokens(data) == 1

    resumed =
      for stream <- streams do
        send(stream, :close_stream)
        assert_receive {:node_mcp_request, "GET", [^token], ["node-workspace"]}, 5_000
        assert_receive {:node_sse_stream, replacement, ["node-event"]}, 5_000
        replacement
      end

    refute_received {:node_rpc, "initialize"}
    assert :closed = rpc(data.first, :close)
    assert_receive {:node_mcp_request, "DELETE", [^token], ["node-workspace"]}, 5_000
    assert rpc(data.second, :session_ready?)
    {:ok, next_expiry, 0} = DateTime.from_iso8601(current.secrets["expires_at"])
    assert :ok = rpc(data.second, :set_now, [DateTime.add(next_expiry, 1)])
    assert :closed = rpc(data.second, :close)
    assert tokens(data) == 1
    refute_received {:node_mcp_request, "DELETE", _, _}
    refute_received {:node_token_response, _, _}
    for stream <- resumed, do: send(stream, :close_stream)
  end
end
