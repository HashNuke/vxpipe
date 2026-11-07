defmodule Vxpipe.Console.MCPCallbackNodesTest do
  use Vxpipe.Console.Test.MCPCallbackNodeCase, async: false

  for mode <- ~w(cimd dcr) do
    @tag mode: mode
    test "#{mode} starts on one node and completes once on another", data do
      handoff = start(data)
      location = authorize(data, handoff)
      assert tokens(data) == 0

      other_session = rpc(data.second, :login)
      rejected = rpc(data.second, :callback, [other_session, location])
      assert error(rejected) == "oauth_attempt_unavailable"
      assert tokens(data) == 0

      response = rpc(data.second, :callback, [data.session, location])
      assert_returned(data, response, handoff, "connected")
      saved = rpc(data.first, :resolve, [data.tenant, handoff["connection_id"]])
      assert saved.connection.server_name == "Fixture calendar"
      assert saved.secrets["registration_method"] == data.mode
      assert Enum.map(saved.connection.catalog, & &1["name"]) == ["list_events"]
      assert tokens(data) == 1
      assert count(data, "tools/call") == 0

      replay = rpc(data.first, :callback, [data.session, location])
      assert error(replay) == "oauth_attempt_unavailable"
      assert tokens(data) == 1
      assert rpc(data.second, :attempt_consumed?, [handoff["attempt_id"]])
      assert rpc(data.second, :connection_count, [data.tenant]) == 1

      assert :ok = rpc(data.first, :refresh, [data.tenant, handoff["connection_id"]])
      renewed = rpc(data.second, :resolve, [data.tenant, handoff["connection_id"]])
      assert renewed.connection == saved.connection
      assert renewed.secrets["grant_revision"] == 2
      assert renewed.secrets["access_token"] != saved.secrets["access_token"]
      assert renewed.secrets["refresh_token"] != saved.secrets["refresh_token"]
      refute Map.has_key?(renewed.secrets, "refresh_claim")
      assert tokens(data) == 2
      assert count(data, "tools/call") == 0
    end
  end

  test "callback survives shutdown of the node that initiated consent", data do
    handoff = start(data)
    location = authorize(data, handoff)
    reference = Process.monitor(data.first)
    :ok = stop_supervised({:mcp_callback_node, 0})
    assert_receive {:DOWN, ^reference, :process, _, :shutdown}

    response = rpc(data.second, :callback, [data.session, location])
    assert_returned(data, response, handoff, "connected")
    assert tokens(data) == 1
    assert rpc(data.second, :attempt_consumed?, [handoff["attempt_id"]])
    assert rpc(data.second, :connection_count, [data.tenant]) == 1
  end

  test "session revocation on another node prevents callback redemption", data do
    handoff = start(data)
    location = authorize(data, handoff)
    assert :ok = rpc(data.first, :logout, [data.session])
    response = rpc(data.second, :callback, [data.session, location])
    assert response.status == 401
    assert error(response) == "session_required"
    assert tokens(data) == 0
    refute rpc(data.second, :attempt_consumed?, [handoff["attempt_id"]])
    assert rpc(data.second, :connection_count, [data.tenant]) == 0
  end

  test "installation URL changed on another node invalidates the callback", data do
    handoff = start(data)
    location = authorize(data, handoff)
    assert :ok = rpc(data.first, :change_installation, [data.session])
    response = rpc(data.second, :callback, [data.session, location])
    assert error(response) == "oauth_attempt_unavailable"
    assert tokens(data) == 0
    refute rpc(data.second, :attempt_consumed?, [handoff["attempt_id"]])
    assert rpc(data.second, :connection_count, [data.tenant]) == 0
  end

  test "tenant service permission loss on another node prevents redemption", data do
    role = rpc(data.first, :create_writer, [data.session, data.tenant])
    writer = rpc(data.first, :login, ["node-writer@example.test"])
    handoff = rpc(data.first, :start, [writer, data.tenant, data.mode])
    location = authorize(data, handoff)
    assert :ok = rpc(data.second, :remove_write_permission, [data.session, role])
    response = rpc(data.first, :callback, [writer, location])
    assert response.status == 401
    assert error(response) == "session_required"
    assert tokens(data) == 0
    refute rpc(data.second, :attempt_consumed?, [handoff["attempt_id"]])
    assert rpc(data.second, :connection_count, [data.tenant]) == 0

    current = rpc(data.first, :login, ["node-writer@example.test"])
    denied = rpc(data.first, :start_response, [current, data.tenant, data.mode])
    assert denied.status == 403
    assert count(data, {"POST", "/register"}) == 1
  end
end
