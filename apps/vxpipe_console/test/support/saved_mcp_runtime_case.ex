defmodule Vxpipe.Console.Test.SavedMCPRuntimeCase do
  use ExUnit.CaseTemplate

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]

  alias ExWebRTC.PeerConnection
  alias Vxpipe.{CallEngine, Calls}
  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}
  alias Vxpipe.Calls.Administration
  alias Vxpipe.CallEngine.RemoteMCPWireServer
  alias Vxpipe.Console.Endpoint
  alias Vxpipe.Console.Test.{FakeUserIdentity, SavedMCPWireConnectionProvider}
  alias Vxpipe.Gateway.{CallAdmission, TestManagedWebPeer}
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

  @token "synthetic-saved-runtime-token"
  @header "synthetic-saved-runtime-header"
  @key "saved-runtime-keyring-marker-123"
  @endpoint Endpoint

  using do
    quote do
      import Phoenix.ConnTest
      import Vxpipe.Console.Test.SavedMCPRuntimeCase
      @moduletag :integration
      @moduletag :capture_log
    end
  end

  setup test do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    sandbox = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(sandbox) end)

    {:ok, keyring} =
      CredentialKeyring.new("fixture", %{"fixture" => @key})

    context = [repo: Repo, keyring: keyring]

    server =
      start_supervised!(
        {RemoteMCPWireServer,
         owner: self(),
         authorization: "Bearer " <> @token,
         headers: [{"x-workspace", @header}],
         hold_stream: Map.get(test, :hold_mcp_stream, false),
         hold_invocation: Map.get(test, :hold_mcp_invocation, false)}
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

    {:ok, other, other_key} =
      Administration.bootstrap_tenant("Other MCP runtime", [:calls], options)

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
      other_secret: other_key.secret,
      principal: principal,
      secret: key.secret,
      options: options,
      context: context,
      connection: connection,
      attributes: attributes
    }
  end

  def configure_admission(options) do
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

  def prepare_web_call(c, source) do
    assert {:ok, draft} = Calls.save_call_spec(c.tenant, source, c.options)
    assert draft.validation_errors == []

    assert {:ok, published} =
             Calls.publish_call_spec(c.tenant, draft.call_spec_id, draft.revision, c.options)

    create_path = "/api/tenants/#{c.tenant}/call-specs/#{published.call_spec_id}/calls"
    prepare_existing_web_call(c, create_path)
  end

  def prepare_existing_web_call(c, create_path) do
    created = api(c.secret, :post, create_path, %{}) |> json_response(201)
    id = created["call"]["id"]
    base = "/api/tenants/#{c.tenant}/calls/#{id}"
    token = api(c.secret, :post, base <> "/join-tokens", %{}) |> json_response(201)
    assert_private_absent(c, [created, token])

    %{
      id: id,
      create_path: create_path,
      secret: token["join_token"]["token"],
      path: base <> "/participants/#{token["participant_key"]}/sessions"
    }
  end

  def admit_web_call(c, prepared) do
    admitted = api(prepared.secret, :post, prepared.path, %{}) |> json_response(201)
    assert {:ok, call} = Calls.fetch_call(c.tenant, prepared.id, c.options)
    assert call.state == :running
    assert_private_absent(c, [admitted, call.plan])
    on_exit(fn -> close_admitted_call(c, call) end)
    {peer, channel} = connect_web(c, admitted["session"]["session_id"])
    %{call: call, peer: peer, channel: channel}
  end

  def model_input(c, active, text) do
    send_web(active.peer, active.channel, "send-text", %{
      content: text,
      options: %{run_immediately: true, audio_response: false}
    })

    assert_receive {:test_agent_runtime_stream, provider, request}, 5_000
    assert_private_absent(c, request)
    assert Enum.any?(request.messages, &(&1.role == :user and &1.content == text))
    {provider, request}
  end

  def finish_text(c, active, provider, text) do
    reply_text(provider, text)
    assert await_web(c, active.peer, active.channel, "bot-output")["data"]["text"] == text
    await_web(c, active.peer, active.channel, "bot-stopped-speaking")
  end

  def failed_admission(c, prepared) do
    response = api(prepared.secret, :post, prepared.path, %{}) |> json_response(503)
    assert response["error"]["code"] == "call_start_failed"
    assert_private_absent(c, response)
    assert {:ok, call} = Calls.fetch_call(c.tenant, prepared.id, c.options)
    assert call.state == :failed
    assert call.incarnation_id == nil
    refute_received {:remote_mcp_wire_request, _, _, _}
  end

  def api(secret, method, path, body) do
    conn = build_conn() |> put_req_header("content-type", "application/json")
    conn = if secret, do: put_req_header(conn, "authorization", "Bearer " <> secret), else: conn
    dispatch(conn, Endpoint, method, "https://localhost" <> path, JSON.encode!(body))
  end

  def disconnect(c) do
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

  def connect_web(c, session_id) do
    peer =
      start_supervised!(
        Supervisor.child_spec({TestManagedWebPeer, controlling_process: self()}, id: make_ref())
      )

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

  def send_web(peer, channel, type, data) do
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

  def await_web(c, peer, channel, type, deadline \\ nil) do
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

  def reply_tool(provider, id, customer) do
    {:ok, tool} =
      ToolCall.new(
        id: id,
        name: "records__lookup_customer",
        arguments: %{"customer_id" => customer}
      )

    {:ok, response} = ModelResponse.new(text: "", tool_calls: [tool])
    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  def await_tool_result(c, id, peer, channel) do
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

  def reply_text(provider, text) do
    {:ok, response} = ModelResponse.new(text: text)
    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  def tool_outcome(request, id, name \\ "records__lookup_customer") do
    message = List.last(request.messages)
    assert message.origin == :engine
    [_instruction, payload] = String.split(message.content, "\n", parts: 2)

    assert %{
             "type" => "tool_invocation_completion",
             "invocation_id" => ^id,
             "tool_name" => ^name,
             "outcome" => outcome
           } = JSON.decode!(payload)

    outcome
  end

  def assert_private_absent(c, value) do
    assert_secret_absent(value)
    refute :erlang.term_to_binary(value) =~ c.connection.endpoint

    for private <- Map.get(c, :private_values, []) do
      refute :erlang.term_to_binary(value) =~ private
    end
  end

  def assert_secret_absent(value) do
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

  def close_admitted_call(c, call) do
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

  def tool(name),
    do: %{
      "name" => name,
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{"customer_id" => %{"type" => "string"}},
        "required" => ["customer_id"]
      }
    }

  def source(id),
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
