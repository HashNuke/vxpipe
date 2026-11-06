defmodule Vxpipe.Console.OutboundMCPOAuthTest do
  use Vxpipe.Console.Test.OutboundMCPOAuthCase, async: false

  for method <- ~w(none client_secret_basic client_secret_post private_key_jwt) do
    @tag mode: "own_client", client_auth_method: method
    test "registered #{method} client connects and safely replaces private configuration",
         data do
      credentials = register_own(data, 0)
      handoff = start(data, nil, credentials)
      assert_connected(data, authorize(data, handoff))
      id = handoff["connection_id"]
      original = resolve(data, id)
      assert original.secrets["auth_method"] == data.client_auth_method
      assert original.secrets["registration_method"] == "own_client"
      assert original.secrets["headers"] == credentials["headers"]
      refute Map.has_key?(original.secrets, "code_verifier")
      assert count(data, {"POST", "/register"}) == 0

      replacement_credentials = register_own(data, 1)
      OutboundMCPOAuthServer.configure(data.peer, %{mcp_fail: true})
      failed = start(data, id, replacement_credentials)
      response = callback(data, authorize(data, failed))
      assert_returned(data, response, "failed", failed["attempt_id"])
      assert resolve(data, id) == original

      OutboundMCPOAuthServer.configure(data.peer, %{mcp_fail: false})
      replacement = start(data, id, replacement_credentials)
      assert resolve(data, id) == original
      assert_connected(data, authorize(data, replacement))
      current = resolve(data, id)
      assert current.connection.generation == 2
      assert current.secrets["headers"] == replacement_credentials["headers"]

      for key <- ~w(client_secret private_key) do
        assert current.secrets[key] == replacement_credentials[key]
      end

      raw = Repo.get_by!(MCPConnection, public_id: id)
      public = request(data, :get, "/mcp-connections/#{id}", %{})
      assert json_response(public, 200)

      for secret <-
            Enum.filter(
              [
                current.secrets["access_token"],
                current.secrets["client_secret"],
                current.secrets["private_key"],
                "workspace-1"
              ],
              &is_binary/1
            ) do
        assert :binary.match(raw.encrypted_payload, secret) == :nomatch
        refute public.resp_body =~ secret
        refute inspect(current) =~ secret
      end

      assert count(data, {"POST", "/register"}) == 0
      assert count(data, {"POST", "/token"}) == 3

      if data.client_auth_method == "private_key_jwt" do
        assert Agent.get(data.peer, &MapSet.size(&1.assertion_ids)) == 3
      end
    end
  end

  for mode <- ["cimd", "dcr"] do
    @tag mode: mode
    test "#{mode} traverses local OAuth/MCP HTTP, encrypted storage and reconnect",
         data do
      discovery =
        request(data, :post, "/mcp-discovery", %{
          "endpoint" => OutboundMCPOAuthServer.resource(),
          "revision" => "draft"
        })

      assert json_response(discovery, 200)["discovery"]["suggested_method"] == data.mode
      assert count(data, {"POST", "/register"}) == 0
      assert count(data, {"POST", "/token"}) == 0
      assert Repo.aggregate(MCPConnection, :count) == 0
      assert Repo.aggregate(MCPOAuthAttempt, :count) == 0

      handoff = start(data)
      attempt = Repo.get_by!(MCPOAuthAttempt, public_id: handoff["attempt_id"])
      assert is_binary(attempt.encrypted_payload)
      assert is_nil(attempt.claimed_at)
      assert Repo.aggregate(MCPConnection, :count) == 0
      callback = authorize(data, handoff)
      assert_connected(data, callback)
      id = handoff["connection_id"]
      first = resolve(data, id)
      assert first.connection.generation == 1
      assert first.connection.server_name == "Fixture calendar"

      assert [%{"name" => "list_events"}] =
               Enum.map(first.connection.catalog, &Map.take(&1, ["name"]))

      assert first.secrets["registration_method"] == data.mode

      assert first.secrets["redirect_uri"] ==
               OutboundMCPOAuthServer.origin() <> "/oauth/mcp/callback"

      assert first.secrets["client_secret_expires_at"] == if(data.mode == "dcr", do: 0, else: nil)
      assert count(data, "initialize") == 1
      assert count(data, "tools/list") == 1
      assert count(data, "tools/call") == 0
      assert count(data, {"POST", "/register"}) == if(data.mode == "dcr", do: 1, else: 0)
      raw = Repo.get_by!(MCPConnection, public_id: id)
      assert :binary.match(raw.encrypted_payload, first.secrets["access_token"]) == :nomatch
      claimed = Repo.get_by!(MCPOAuthAttempt, public_id: handoff["attempt_id"])
      assert claimed.claimed_at
      assert is_nil(claimed.encrypted_payload)

      replay = callback(data, callback)
      assert json_response(replay, 400)["error"]["code"] == "oauth_attempt_unavailable"
      assert count(data, {"POST", "/token"}) == 1

      replacement = start(data, id)
      assert resolve(data, id).secrets == first.secrets
      assert count(data, {"POST", "/register"}) == if(data.mode == "dcr", do: 1, else: 0)
      assert_connected(data, authorize(data, replacement))
      replaced = resolve(data, id)
      assert replaced.connection.generation == 2
      assert replaced.connection.id == id
      refute replaced.secrets["access_token"] == first.secrets["access_token"]
      assert Repo.aggregate(MCPConnection, :count) == 1

      assert json_response(
               request(data, :delete, "/mcp-connections/#{id}", %{"generation" => 2}),
               200
             )

      assert {:error, :mcp_connection_revoked} =
               ConnectionStore.resolve(data.context, data.tenant, id)

      assert is_nil(Repo.get_by!(MCPConnection, public_id: id).encrypted_payload)

      restored_attempt = start(data, id, nil, 3)
      assert count(data, {"POST", "/register"}) == if(data.mode == "dcr", do: 2, else: 0)
      assert_connected(data, authorize(data, restored_attempt))
      restored = resolve(data, id)
      assert restored.connection.id == id
      assert restored.connection.namespace == first.connection.namespace
      assert restored.connection.generation == 4
      assert Repo.aggregate(MCPConnection, :count) == 1
      assert count(data, "tools/call") == 0
    end
  end

  test "denied consent, failed MCP initialization and revocation preserve replacement boundaries",
       data do
    initial = start(data)
    assert_connected(data, authorize(data, initial))
    id = initial["connection_id"]
    original = resolve(data, id)

    OutboundMCPOAuthServer.configure(data.peer, %{consent: :deny})
    denied = start(data, id)
    response = callback(data, authorize(data, denied))
    assert_returned(data, response, "denied", denied["attempt_id"])
    assert count(data, {"POST", "/token"}) == 1
    assert resolve(data, id) == original

    OutboundMCPOAuthServer.configure(data.peer, %{consent: :allow, mcp_fail: true})
    failed = start(data, id)
    response = callback(data, authorize(data, failed))
    assert_returned(data, response, "failed", failed["attempt_id"])
    assert count(data, {"POST", "/token"}) == 2
    assert resolve(data, id) == original

    OutboundMCPOAuthServer.configure(data.peer, %{mcp_fail: false})
    stale = start(data, id)
    location = authorize(data, stale)

    assert json_response(
             request(data, :delete, "/mcp-connections/#{id}", %{"generation" => 1}),
             200
           )

    assert_returned(data, callback(data, location), "failed", stale["attempt_id"])
    assert count(data, {"POST", "/token"}) == 2

    assert {:error, :mcp_connection_revoked} =
             ConnectionStore.resolve(data.context, data.tenant, id)
  end

  test "a successful MCP check queued past the callback deadline cannot persist a grant", data do
    handoff = start(data)
    location = authorize(data, handoff)
    owner = self()
    tasks = start_supervised!({Task.Supervisor, name: nil}, id: :completion_tasks)

    runner =
      start_supervised!(
        {Vxpipe.MCP.PreflightRunner,
         name: nil, task_supervisor: tasks, timeout: 750, interval: 0},
        id: :completion_runner
      )

    protocol =
      OutboundMCPOAuthServer.options(data.peer)
      |> Keyword.put(:completion_runner, runner)
      |> Keyword.put(:connection_check, fn _, _ ->
        send(owner, {:checked, self()})

        receive do
          :release -> {:ok, %{server_name: "Late server", catalog: []}}
        end
      end)

    calls = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)

    Application.put_env(
      :vxpipe_calls,
      Vxpipe.Calls,
      Keyword.put(calls, :mcp_oauth_completion, {Vxpipe.Console.MCPOAuthCompletion, protocol})
    )

    start_supervised!({Task, fn -> send(owner, {:callback, callback(data, location)}) end})
    assert_receive {:checked, worker}, 1_000
    monitor = Process.monitor(worker)
    :ok = :sys.suspend(runner)
    send(worker, :release)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 1_000
    Process.send_after(self(), :deadline_passed, 800)
    assert_receive :deadline_passed, 2_000
    :ok = :sys.resume(runner)
    assert_receive {:callback, response}, 1_000
    assert_returned(data, response, "failed", handoff["attempt_id"])
    assert Repo.aggregate(MCPConnection, :count) == 0
    attempt = Repo.get_by!(MCPOAuthAttempt, public_id: handoff["attempt_id"])
    assert attempt.claimed_at
    assert is_nil(attempt.encrypted_payload)
    assert count(data, {"POST", "/token"}) == 1
  end
end
