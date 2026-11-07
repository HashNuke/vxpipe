defmodule Vxpipe.Console.Integration.SavedMCPRuntimeTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]

  alias ExWebRTC.PeerConnection
  alias Vxpipe.{CallEngine, Calls}
  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}
  alias Vxpipe.Calls.{Administration, EditorToolCatalog}
  alias Vxpipe.CallEngine.RemoteMCP.IntegrationOwner
  alias Vxpipe.CallEngine.RemoteMCPWireServer
  alias Vxpipe.Console.Test.SavedMCPWireConnectionProvider
  alias Vxpipe.Console.Test.FakeUserIdentity
  alias Vxpipe.Console.Endpoint
  alias Vxpipe.Gateway.{CallAdmission, TestManagedWebPeer}
  alias Vxpipe.Gateway.CallAdmission.CallEngineOptions
  alias Vxpipe.Gateway.HTTP.Mount
  alias Vxpipe.MCP.{ConnectionKey, Connections}

  alias Vxpipe.Persistence.{
    AccessKeyStore,
    CallSpecStore,
    CallStore,
    CredentialKeyring,
    CredentialStore,
    Repo
  }

  alias Vxpipe.Persistence.MCP.ConnectionStore

  @moduletag :integration
  @moduletag :capture_log
  @token "synthetic-saved-runtime-token"
  @header "synthetic-saved-runtime-header"
  @key "saved-runtime-keyring-marker-123"
  @endpoint Endpoint

  setup do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    sandbox = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(sandbox) end)

    {:ok, keyring} =
      CredentialKeyring.new("fixture", %{"fixture" => @key})

    context = [repo: Repo, keyring: keyring]

    server =
      start_supervised!(
        {RemoteMCPWireServer,
         owner: self(), authorization: "Bearer " <> @token, headers: [{"x-workspace", @header}]}
      )

    %URI{port: port} = URI.parse(RemoteMCPWireServer.endpoint(server))
    endpoint = "https://mcp.example.test:#{port}/mcp"

    options = [
      access_key_repository: {AccessKeyStore, Repo},
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      mcp_connection_repository: {ConnectionStore, context},
      registries: %{host_tools: %{}}
    ]

    configured = Application.get_env(:vxpipe_calls, Calls, [])
    Application.put_env(:vxpipe_calls, Calls, Keyword.merge(configured, options))
    on_exit(fn -> Application.put_env(:vxpipe_calls, Calls, configured) end)

    {:ok, tenant, key} = Administration.bootstrap_tenant("Saved MCP runtime", [:calls], options)
    {:ok, principal} = Administration.authenticate(tenant.key, key.secret, :calls, options)
    {:ok, other, _} = Administration.bootstrap_tenant("Other MCP runtime", [:calls], options)

    attributes = %{
      endpoint: endpoint,
      endpoint_identity: endpoint,
      server_name: "Records",
      auth_method: "bearer",
      catalog: [tool("lookup_customer")]
    }

    {:ok, connection} =
      ConnectionStore.create(context, tenant.key, attributes, %{
        "token" => @token,
        "headers" => [%{"name" => "X-Workspace", "value" => @header}]
      })

    %{
      tenant: tenant.key,
      other: other.key,
      principal: principal,
      secret: key.secret,
      options: options,
      context: context,
      connection: connection,
      attributes: attributes
    }
  end

  test "an admitted web call executes its saved MCP tool and observes tenant disconnect", c do
    configure_admission(c.options)
    assert {:ok, draft} = Calls.save_call_spec(c.tenant, source(c.connection.id), c.options)
    assert draft.validation_errors == []

    assert {:ok, published} =
             Calls.publish_call_spec(c.tenant, draft.call_spec_id, draft.revision, c.options)

    created =
      api(
        c.secret,
        :post,
        "/api/tenants/#{c.tenant}/call-specs/#{published.call_spec_id}/calls",
        %{}
      )
      |> json_response(201)

    id = created["call"]["id"]
    base = "/api/tenants/#{c.tenant}/calls/#{id}"
    token = api(c.secret, :post, base <> "/join-tokens", %{}) |> json_response(201)
    join_path = base <> "/participants/#{token["participant_key"]}/sessions"
    join_secret = token["join_token"]["token"]

    # Reject browser-supplied adapters before consuming the single-use join token.
    assert %{"error" => %{"code" => "invalid_request"}} =
             api(join_secret, :post, join_path, %{
               "remote_mcp_connection_provider" => "untrusted"
             })
             |> json_response(400)

    admitted = api(join_secret, :post, join_path, %{}) |> json_response(201)
    assert {:ok, call} = Calls.fetch_call(c.tenant, id, c.options)
    assert call.state == :running
    assert admitted["call"]["state"] == "running"
    assert_private_absent(c, [created, token, admitted, call.plan])
    on_exit(fn -> close_admitted_call(c, call) end)

    {peer, channel} = connect_web(c, admitted["session"]["session_id"])

    send_web(peer, channel, "send-text", %{
      content: "Find customer-42.",
      options: %{run_immediately: true, audio_response: false}
    })

    assert_receive {:test_agent_runtime_stream, provider, request}, 5_000
    assert Enum.map(request.tools, & &1.name) == ["records__lookup_customer"]
    assert_private_absent(c, request)
    reply_tool(provider, "saved-first", "customer-42")

    assert_receive {:remote_mcp_wire_request, "tools/call", "Bearer " <> @token,
                    %{
                      "params" => %{
                        "name" => "lookup_customer",
                        "arguments" => %{"customer_id" => "customer-42"}
                      }
                    }},
                   5_000

    {completion, result} = await_tool_result(c, "saved-first", peer, channel)
    assert_private_absent(c, result)

    assert %{
             "status" => "completed",
             "result" => %{"content" => [%{"type" => "text", "text" => "found customer-42"}]}
           } = tool_outcome(result, "saved-first")

    reply_text(completion, "I found customer-42.")
    assert await_web(c, peer, channel, "bot-output")["data"]["text"] == "I found customer-42."
    await_web(c, peer, channel, "bot-stopped-speaking")

    disconnected = disconnect(c) |> json_response(200)
    assert disconnected["connection"]["status"] == "revoked"
    assert_secret_absent(disconnected)

    send_web(peer, channel, "send-text", %{
      content: "Now find customer-43.",
      options: %{run_immediately: true, audio_response: false}
    })

    assert_receive {:test_agent_runtime_stream, next_provider, next_request}, 5_000
    assert_private_absent(c, next_request)
    reply_tool(next_provider, "saved-after-disconnect", "customer-43")
    {failed_provider, failure} = await_tool_result(c, "saved-after-disconnect", peer, channel)
    assert_private_absent(c, failure)
    assert tool_outcome(failure, "saved-after-disconnect") == %{"status" => "failed"}
    refute_received {:remote_mcp_wire_request, "tools/call", _, _}
    reply_text(failed_provider, "The records connection is unavailable.")

    assert await_web(c, peer, channel, "bot-output")["data"]["text"] ==
             "The records connection is unavailable."

    await_web(c, peer, channel, "bot-stopped-speaking")
    assert {:ok, still_running} = Calls.fetch_call(c.tenant, id, c.options)
    assert still_running.state == :running
    assert still_running.incarnation_id == call.incarnation_id
    close_admitted_call(c, call)
    refute_received {:remote_mcp_wire_request, "tools/call", _, _}
  end

  test "saved publication and preparation stay secret-free, then wire execution rechecks revocation",
       c do
    # Authoring can read metadata even when no decryption key is available.
    metadata_options =
      Keyword.put(
        c.options,
        :mcp_connection_repository,
        {ConnectionStore, Keyword.put(c.context, :keyring, :unconfigured)}
      )

    assert Enum.any?(
             EditorToolCatalog.list(c.tenant, metadata_options).tools,
             &(&1.type == "mcp" and &1.integration == c.connection.id)
           )

    refute Enum.any?(EditorToolCatalog.list(c.other, metadata_options).tools, &(&1.type == "mcp"))
    {call, route} = published_call(c, metadata_options)
    assert {:ok, stored} = Calls.fetch_call(c.tenant, call.id, c.options)

    for private <- [@token, c.connection.endpoint, "runtime_authentication", "client_config"] do
      refute :erlang.term_to_binary(stored.plan) =~ private
    end

    assert {:ok, runtime} = CallEngineOptions.build(c.options, stored)

    {:ok, key} =
      ConnectionKey.new(
        scope: :tenant,
        tenant_id: c.tenant,
        integration_id: c.connection.id,
        credential_generation: "1"
      )

    on_exit(fn -> Connections.close(key) end)

    owner =
      start_supervised!(
        {IntegrationOwner,
         activation_id: call.id,
         tools: call.plan.participants["assistant"].tools,
         integrations: Keyword.fetch!(runtime, :mcp_catalog_store),
         connection_provider: SavedMCPWireConnectionProvider}
      )

    assert {:ok, %{"content" => [%{"text" => "found customer-42"}]}} =
             IntegrationOwner.execute(owner, "records__lookup_customer", %{
               "customer_id" => "customer-42"
             })

    assert_receive {:remote_mcp_wire_request, "tools/call", "Bearer " <> @token, _}, 2_000
    assert {:ok, _} = ConnectionStore.revoke(c.context, c.tenant, c.connection.id, 1)

    assert {:error, :tool_failed} =
             IntegrationOwner.execute(owner, "records__lookup_customer", %{
               "customer_id" => "customer-43"
             })

    refute_received {:remote_mcp_wire_request, "tools/call", _, _}
    assert {:error, :mcp_connection_unavailable} = CallEngineOptions.build(c.options, stored)
    assert {:error, _} = Calls.prepare_call(c.principal, route.key, %{}, c.options)
  end

  test "schema refresh and credential replacement invalidate prepared pins without granting new tools",
       c do
    {call, route} = published_call(c, c.options)

    assert {:ok, _} =
             ConnectionStore.refresh_catalog(c.context, c.tenant, c.connection.id, 1, %{
               catalog: [tool("lookup_customer"), tool("new_tool")],
               server_name: "Renamed records"
             })

    assert {:error, :mcp_connection_unavailable} = CallEngineOptions.build(c.options, call)
    assert {:ok, refreshed, _} = Calls.prepare_call(c.principal, route.key, %{}, c.options)

    assert Map.keys(refreshed.plan.participants["assistant"].tools) == [
             "records__lookup_customer"
           ]

    assert {:ok, _} = CallEngineOptions.build(c.options, refreshed)

    assert {:ok, _} =
             ConnectionStore.replace(c.context, c.tenant, c.connection.id, 1, c.attributes, %{
               "token" => "replacement-token"
             })

    assert {:error, :mcp_connection_unavailable} = CallEngineOptions.build(c.options, refreshed)

    assert {:error, :mcp_connection_unavailable} =
             CallEngineOptions.build(c.options, %{call | tenant_key: c.other})
  end

  defp published_call(c, options) do
    assert {:ok, draft} = Calls.save_call_spec(c.tenant, source(c.connection.id), options)
    assert draft.validation_errors == []

    assert {:ok, published} =
             Calls.publish_call_spec(c.tenant, draft.call_spec_id, draft.revision, options)

    route = Enum.find(published.routes, &(&1.participant_ref == "caller"))
    assert {:ok, call, _token} = Calls.prepare_call(c.principal, route.key, %{}, options)
    {call, route}
  end

  test "supervised saved connection retirement keeps credentials out of OTP reports", c do
    :ok =
      :logger.add_primary_filter(
        :saved_mcp_runtime_capture,
        {fn event, owner ->
           send(owner, {:check_log, event})
           event
         end, self()}
      )

    on_exit(fn -> :logger.remove_primary_filter(:saved_mcp_runtime_capture) end)
    {call, _} = published_call(c, c.options)
    {:ok, runtime} = CallEngineOptions.build(c.options, call)

    {:ok, key} =
      ConnectionKey.new(
        scope: :tenant,
        tenant_id: c.tenant,
        integration_id: c.connection.id,
        credential_generation: "1"
      )

    on_exit(fn -> Connections.close(key) end)

    options = [
      activation_id: call.id,
      tools: call.plan.participants["assistant"].tools,
      integrations: Keyword.fetch!(runtime, :mcp_catalog_store),
      connection_provider: SavedMCPWireConnectionProvider
    ]

    spec = Supervisor.child_spec({IntegrationOwner, options}, restart: :permanent)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        supervisor =
          start_supervised!(%{
            id: :saved_mcp_owner_supervisor,
            start: {Supervisor, :start_link, [[spec], [strategy: :one_for_one]]}
          })

        [{_, owner, _, _}] = Supervisor.which_children(supervisor)
        monitor = Process.monitor(owner)
        send(owner, {:vxpipe_mcp_credential_revoked, key})
        assert_receive {:DOWN, ^monitor, :process, ^owner, :credential_revoked}, 2_000
        [{_, replacement, _, _}] = Supervisor.which_children(supervisor)
        replacement_monitor = Process.monitor(replacement)
        {:ok, connection} = Connections.lookup(key)
        client = Vxpipe.MCP.Connection.client(connection)
        :ok = GenServer.stop(client, :fixture_connection_lost)

        assert_receive {:DOWN, ^replacement_monitor, :process, ^replacement, :connection_lost},
                       2_000

        _ = Supervisor.which_children(supervisor)
      end)

    Logger.flush()
    reports = collect_reports()

    assert Enum.any?(reports, fn event ->
             case event do
               %{msg: {:report, %{label: {:supervisor, _}}}} -> true
               _ -> false
             end
           end)

    for marker <- [@token, @header, @key] do
      refute log =~ marker
      refute :erlang.term_to_binary(reports) =~ marker
    end
  end

  defp collect_reports do
    receive do
      {:check_log, event} -> [event | collect_reports()]
    after
      0 -> []
    end
  end

  defp configure_admission(options) do
    mount = Endpoint.config(:gateway_mount)
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)
    identity = Application.get_env(:vxpipe_console, :user_identity_backend)

    runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:fixture, {Vxpipe.CallEngine.TestAgentRuntimeModelProvider, [owner: self()]})

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :agent_runtime, runtime)
    )

    Application.put_env(:vxpipe_console, :user_identity_backend, FakeUserIdentity)

    configured =
      Keyword.put(options, :remote_mcp_connection_provider, SavedMCPWireConnectionProvider)

    Phoenix.Config.put(
      Endpoint,
      :gateway_mount,
      Mount.init(call_admission: [enabled: true, backend: {CallAdmission, configured}])
    )

    on_exit(fn ->
      Phoenix.Config.put(Endpoint, :gateway_mount, mount)
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
      Application.put_env(:vxpipe_console, :user_identity_backend, identity)
    end)
  end

  defp api(secret, method, path, body) do
    conn = build_conn() |> put_req_header("content-type", "application/json")
    conn = if secret, do: put_req_header(conn, "authorization", "Bearer " <> secret), else: conn
    dispatch(conn, Endpoint, method, "https://localhost" <> path, JSON.encode!(body))
  end

  defp disconnect(c) do
    page =
      build_conn()
      |> post("https://localhost/auth/api/login", %{
        email: FakeUserIdentity.email(),
        password: FakeUserIdentity.password()
      })
      |> recycle()
      |> get("https://localhost/account")

    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, page.resp_body)
    conn = page |> recycle() |> put_req_header("x-csrf-token", csrf)
    conn = %{conn | private: Map.delete(conn.private, :plug_skip_csrf_protection)}

    delete(
      conn,
      "https://localhost/api/tenants/#{c.tenant}/mcp-connections/#{c.connection.id}",
      %{"generation" => 1}
    )
  end

  defp connect_web(c, session_id) do
    peer = start_supervised!({TestManagedWebPeer, controlling_process: self()})
    :ok = PeerConnection.controlling_process(peer, self())
    {:ok, channel} = PeerConnection.create_data_channel(peer, "chat", ordered: true)
    offer = TestManagedWebPeer.offer(peer)

    answer =
      api(nil, :post, "/api/rtvi/offer", %{
        sdp: offer,
        type: "offer",
        pc_id: nil,
        restart_pc: false,
        requestData: %{session_id: session_id}
      })
      |> json_response(200)

    :ok = TestManagedWebPeer.answer(peer, answer["sdp"])
    assert_receive {:ex_webrtc, ^peer, {:ice_candidate, candidate}}, 5_000

    assert api(nil, :patch, "/api/rtvi/offer", %{
             pc_id: answer["pc_id"],
             candidates: [TestManagedWebPeer.candidate(candidate)]
           }).status == 200

    assert_receive {:ex_webrtc, ^peer, {:connection_state_change, :connected}}, 5_000
    ref = channel.ref
    assert_receive {:ex_webrtc, ^peer, {:data_channel_state_change, ^ref, :open}}, 5_000

    :ok =
      PeerConnection.send_data(
        peer,
        ref,
        JSON.encode!(%{
          type: "signalling",
          message: %{type: "trackStatus", receiver_index: 0, enabled: true}
        })
      )

    send_web(peer, ref, "client-ready", %{
      version: "2.1.0",
      about: %{library: "@pipecat-ai/client-js", library_version: "1.13.0"}
    })

    await_web(c, peer, ref, "bot-ready")
    {peer, ref}
  end

  defp send_web(peer, channel, type, data) do
    :ok =
      PeerConnection.send_data(
        peer,
        channel,
        JSON.encode!(%{
          id: "saved-#{System.unique_integer([:positive])}",
          label: "rtvi-ai",
          type: type,
          data: data
        })
      )
  end

  defp await_web(c, peer, channel, type, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 5_000

    receive do
      {:ex_webrtc, ^peer, {:data, ^channel, data}} ->
        message = JSON.decode!(data)
        assert_private_absent(c, message)
        if message["type"] == type, do: message, else: await_web(c, peer, channel, type, deadline)
    after
      max(0, deadline - System.monotonic_time(:millisecond)) -> flunk("Missing RTVI #{type}")
    end
  end

  defp reply_tool(provider, id, customer) do
    {:ok, tool} =
      ToolCall.new(
        id: id,
        name: "records__lookup_customer",
        arguments: %{"customer_id" => customer}
      )

    {:ok, response} = ModelResponse.new(text: "", tool_calls: [tool])
    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  defp await_tool_result(c, id, peer, channel) do
    assert_receive {:test_agent_runtime_stream, acknowledgement, pending}, 5_000
    assert_private_absent(c, pending)
    assert pending.tools == []

    assert Enum.any?(pending.messages, fn message ->
             message.role == :tool and message.tool_call_id == id and
               JSON.decode!(message.content) == %{"invocation_id" => id, "status" => "running"}
           end)

    reply_text(acknowledgement, "Checking records.")
    assert await_web(c, peer, channel, "bot-output")["data"]["text"] == "Checking records."
    await_web(c, peer, channel, "bot-stopped-speaking")
    assert_receive {:test_agent_runtime_stream, provider, result}, 5_000
    {provider, result}
  end

  defp reply_text(provider, text) do
    {:ok, response} = ModelResponse.new(text: text)
    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  defp tool_outcome(request, id) do
    message = List.last(request.messages)
    assert message.origin == :engine
    [_instruction, payload] = String.split(message.content, "\n", parts: 2)

    assert %{
             "type" => "tool_invocation_completion",
             "invocation_id" => ^id,
             "tool_name" => "records__lookup_customer",
             "outcome" => outcome
           } = JSON.decode!(payload)

    outcome
  end

  defp assert_private_absent(c, value) do
    assert_secret_absent(value)
    refute :erlang.term_to_binary(value) =~ c.connection.endpoint
  end

  defp assert_secret_absent(value) do
    for private <- [
          @token,
          @header,
          @key,
          "runtime_authentication",
          "client_config"
        ] do
      refute :erlang.term_to_binary(value) =~ private
    end
  end

  defp close_admitted_call(c, call) do
    case CallEngine.monitor_room_completion(c.tenant, call.room_id, call.incarnation_id) do
      {:ok, monitor} ->
        CallEngine.end_call(c.tenant, call.room_id, call.incarnation_id)
        assert_receive {:DOWN, ^monitor, :process, _, _}, 5_000

      {:error, _} ->
        :ok
    end

    {:ok, key} =
      ConnectionKey.new(
        scope: :tenant,
        tenant_id: c.tenant,
        integration_id: c.connection.id,
        credential_generation: "1"
      )

    Connections.close(key)
  end

  defp tool(name),
    do: %{
      "name" => name,
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{"customer_id" => %{"type" => "string"}},
        "required" => ["customer_id"]
      }
    }

  defp source(id),
    do: %{
      schema_version: "20260915.01",
      wait_sounds: %{call_setup: nil},
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Use the records tool.",
          first_message: %{mode: "wait_for_input"},
          capabilities: %{model_inference: %{provider: "fixture", model: "test"}},
          tools: %{
            "records__lookup_customer" => %{type: "mcp", integration: id, tool: "lookup_customer"}
          },
          transfers: []
        }
      }
    }
end
