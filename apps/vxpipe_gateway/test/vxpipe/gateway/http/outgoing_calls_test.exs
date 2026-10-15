defmodule Vxpipe.Gateway.HTTP.OutgoingCallsTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log
  import Plug.Conn
  import Plug.Test

  alias Vxpipe.CallEngine.TestOutboundLegConnector
  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, TestMemoryRepository, TestTelephonyServiceRepository}
  alias Vxpipe.Gateway.CallAdmission
  alias Vxpipe.Gateway.HTTP.Endpoint

  setup do
    repository = start_supervised!(TestMemoryRepository)

    options = [
      credential_repository: {TestMemoryRepository, repository},
      call_spec_repository: {TestMemoryRepository, repository},
      call_repository: {TestMemoryRepository, repository},
      registries: %{host_tools: %{}}
    ]

    assert {:ok, tenant, key} =
             Administration.bootstrap_tenant("Outgoing HTTP", [:calls], options)

    assert {:ok, principal} = Calls.authenticate(tenant.key, key.secret, :calls, options)

    assert {:ok, _tenant, admin} =
             Administration.bootstrap_tenant("Admin only", [:admin], options)

    options =
      Keyword.put(
        options,
        :telephony_service_repository,
        TestTelephonyServiceRepository.repository([tenant])
      )

    assert {:ok, draft} = Calls.save_call_spec(tenant.key, source(), options)
    assert {:ok, published} = Calls.publish_call_spec(tenant.key, draft.call_spec_id, 1, options)
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(
        :fixture,
        {Vxpipe.CallEngine.TestSelectiveAgentRuntimeModelProvider, [owner: self()]}
      )

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :agent_runtime, runtime)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    %{
      options: options,
      tenant: tenant,
      principal: principal,
      key: key,
      admin: admin,
      published: published,
      observer: self()
    }
  end

  test "managed outgoing startup rejects connectors without cleanup ownership before dialing",
       c do
    c = %{c | options: Keyword.put(c.options, :managed_cleanup, true)}
    response = post(c, %{}, "managed-custom-connector")
    assert response.status == 503
    refute_received {:test_outbound_leg_connect, _, _, _}
  end

  test "routes before spec writes and returns a private-free 201 after submission", c do
    response =
      post(
        c,
        %{"variables" => %{"data" => %{"private" => "private-sentinel"}}},
        "request-key"
      )

    assert response.status == 201
    assert get_resp_header(response, "access-control-allow-origin") == []

    assert %{
             "call" => %{
               "id" => id,
               "call_spec_id" => spec_id,
               "revision" => 1,
               "state" => "running",
               "outgoing_outcome" => nil
             }
           } = body(response)

    assert spec_id == c.published.call_spec_id
    refute response.resp_body =~ "private-sentinel"
    refute response.resp_body =~ "request-key"
    refute response.resp_body =~ c.key.secret
    assert_receive {:test_outbound_leg_connect, _, request, _}, 1_000
    assert request.purpose == :initial
    assert request.call_id == id
    assert {:ok, stored} = Calls.fetch_call(c.tenant.key, id, c.options)
    assert stored.incarnation_id == request.incarnation_id
    assert stored.state == :running
  end

  test "MCP outgoing creation has its own bounded deadline and HTTP replay never redials", c do
    {configured, session} = mcp_endpoint(c, block?: true, call_creation_timeout: 2_000)
    variables = %{"data" => %{"private" => "mcp-pinned-sentinel"}}
    tasks = start_supervised!({Task.Supervisor, name: nil})

    task =
      Task.Supervisor.async_nolink(tasks, fn ->
        mcp_tool(c, configured, session, 2, "create_call", %{
          tenant_key: c.tenant.key,
          call_spec_id: c.published.call_spec_id,
          variables: variables,
          idempotency_key: "mcp-dial"
        })
      end)

    assert_receive {:test_outbound_leg_connect, worker, request, _}, 1_000
    {:ok, pinned} = Calls.fetch_call(c.tenant.key, request.call_id, c.options)
    assert pinned.state == :running
    assert pinned.plan.call_variables.sections["data"].value == variables["data"]
    reference = task.ref
    refute_receive {^reference, _response}, 50
    send(worker, :release_test_dial)
    response = Task.await(task, 2_000)
    id = request.call_id
    assert response.status == 200

    assert %{
             "result" => %{
               "isError" => false,
               "structuredContent" => %{"call_id" => ^id} = result
             }
           } = body(response)

    assert map_size(result) == 1
    refute response.resp_body =~ "mcp-pinned-sentinel"

    replay = post(c, %{"variables" => variables}, "mcp-dial")
    assert replay.status == 200
    assert body(replay)["call"]["id"] == id
    refute_received {:test_outbound_leg_connect, _, _, _}
  end

  test "the longer creation deadline does not extend unrelated MCP tools", c do
    options = Keyword.put(c.options, :admin_repository, {__MODULE__, self()})
    {configured, session} = mcp_endpoint(%{c | options: options}, call_creation_timeout: 2_000)
    response = mcp_tool(c, configured, session, 2, "get_tenant", %{tenant_key: c.tenant.key})
    assert %{"error" => %{"code" => -32603}} = body(response)
    assert_receive {:directory_blocked, handler}, 1_000
    monitor = Process.monitor(handler)
    assert_receive {:DOWN, ^monitor, :process, ^handler, _reason}, 1_000
  end

  test "an expired MCP creation deadline retains the durable idempotency claim", c do
    {configured, session} = mcp_endpoint(c, block?: true, call_creation_timeout: 500)
    tasks = start_supervised!({Task.Supervisor, name: nil})

    task =
      Task.Supervisor.async_nolink(tasks, fn ->
        mcp_tool(c, configured, session, 2, "create_call", %{
          tenant_key: c.tenant.key,
          call_spec_id: c.published.call_spec_id,
          idempotency_key: "mcp-timeout"
        })
      end)

    assert_receive {:test_outbound_leg_connect, worker, request, _}, 1_000
    response = Task.await(task, 2_000)
    assert %{"error" => %{"code" => -32603}} = body(response)
    # The provider may already have received the submission when a client times out.
    # Retrying the same durable claim must never issue a second dial.
    send(worker, :release_test_dial)
    replay = post(c, %{}, "mcp-timeout")
    id = request.call_id

    case body(replay) do
      %{"call" => %{"id" => ^id}} ->
        assert replay.status == 200

      %{"error" => %{"code" => code}} ->
        assert replay.status == 503
        assert code in ["outgoing_call_start_failed", "outgoing_submission_unknown"]
    end

    {:ok, stored} = Calls.fetch_call(c.tenant.key, request.call_id, c.options)
    assert stored.idempotency_key == "mcp-timeout"
    refute_received {:test_outbound_leg_connect, _, _, _}
  end

  def tenant_candidates(owner, _scope, _limit) do
    send(owner, {:directory_blocked, self()})
    receive do: (:release_directory -> {:ok, []})
  end

  test "a published web spec prepares one call with variables and no token or runtime", c do
    web =
      source()
      |> Map.delete(:outgoing_call)
      |> Map.put(:incoming_call, %{caller: "callee", handled_by: "assistant"})
      |> put_in([:participants, "callee", :connection], %{
        service: "web",
        mode: "receive",
        admission: "start_call"
      })

    {:ok, draft} = Calls.save_call_spec(c.tenant.key, web, c.options)
    {:ok, _} = Calls.publish_call_spec(c.tenant.key, draft.call_spec_id, 1, c.options)

    c = %{
      c
      | options:
          Keyword.put(c.options, :join_token_generator, fn -> flunk("unexpected token") end)
    }

    input = %{"variables" => %{"data" => %{"private" => "pinned value"}}}
    response = post(c, input, "web-retry", spec: draft.call_spec_id)
    assert response.status == 201
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert %{"call" => %{"id" => id, "state" => "prepared", "revision" => 1}} = body(response)
    {:ok, stored} = Calls.fetch_call(c.tenant.key, id, c.options)
    assert stored.initial_variables == input["variables"]
    assert stored.incarnation_id == nil
    refute Map.has_key?(body(response), "join_token")
    refute response.resp_body =~ "pinned value"
    assert post(c, input, "web-retry", spec: draft.call_spec_id).status == 200
    assert post(c, %{}, "web-retry", spec: draft.call_spec_id).status == 409

    {:ok, token} =
      Calls.issue_call_join_token(
        c.principal,
        c.tenant.key,
        id,
        nil,
        Keyword.delete(c.options, :join_token_generator)
      )

    {:ok, claim} =
      Calls.claim_join_token(
        token.secret,
        %{tenant_key: c.tenant.key, call_id: id, participant_key: token.participant_key},
        c.options
      )

    {:ok, _} = Calls.mark_call_failed(claim, :startup_unknown, c.options)
    replay = post(c, input, "web-retry", spec: draft.call_spec_id)
    assert replay.status == 200
    assert body(replay)["call"]["state"] == "failed"
    refute_received {:test_outbound_leg_connect, _, _, _}
  end

  test "browser call creation uses the same actor policy and explicit keys never fall back", c do
    browser = %Vxpipe.Identity.Principal{
      user_public_id: "user",
      session_public_id: "session",
      account_kind: :member,
      grants: MapSet.new(["calls.write"]),
      assigned_tenants: %{c.tenant.key => :read_write},
      all_tenant_actions: MapSet.new()
    }

    configured = endpoint(c, browser_auth: {__MODULE__, browser})
    assert post(c, %{}, nil, secret: nil, endpoint: configured).status == 201
    assert_receive {:test_outbound_leg_connect, _, _, _}, 1_000
    assert post(c, %{}, nil, secret: "invalid", endpoint: configured).status == 401
    denied = endpoint(c, browser_auth: {__MODULE__, %{browser | grants: MapSet.new()}})
    assert post(c, %{}, nil, secret: nil, endpoint: denied).status == 403
    refute_received {:test_outbound_leg_connect, _, _, _}
  end

  test "browser authentication failure returns a fixed error without private diagnostics", c do
    configured = endpoint(c, browser_auth: {__MODULE__, :unavailable})
    response = post(c, %{}, nil, secret: nil, endpoint: configured)
    assert response.status == 503
    assert body(response)["error"]["code"] == "call_management_unavailable"
    refute response.resp_body =~ "private-browser-sentinel"
    refute_received {:test_outbound_leg_connect, _, _, _}
  end

  def authenticate(_conn, :unavailable), do: raise("private-browser-sentinel")
  def authenticate(conn, actor), do: {:ok, conn, actor}

  test "durable start precedes dialing and 201 waits for its acknowledgement", c do
    task = Task.async(fn -> post(c, %{}, nil, block?: true) end)
    assert_receive {:test_outbound_leg_connect, worker, request, _}, 2_000
    assert {:ok, stored} = Calls.fetch_call(c.tenant.key, request.call_id, c.options)
    assert stored.state == :running
    reference = task.ref
    refute_received {^reference, _response}
    send(worker, :release_test_dial)
    assert Task.await(task, 2_000).status == 201
  end

  test "same-key retries and concurrent duplicates submit one dial", c do
    first = post(c, %{}, "idempotent")
    assert first.status == 201
    second = post(c, %{}, "idempotent")
    assert second.status == 200
    assert body(second) == body(first)
    assert_receive {:test_outbound_leg_connect, _, _, _}, 1_000
    refute_receive {:test_outbound_leg_connect, _, _, _}, 30

    conflict =
      post(c, %{"variables" => %{"data" => %{"private" => "changed"}}}, "idempotent")

    assert conflict.status == 409
    assert %{"error" => %{"code" => "idempotency_conflict"}} = body(conflict)

    endpoint = endpoint(c, block?: true)
    first = Task.async(fn -> post(c, %{}, "concurrent", endpoint: endpoint) end)
    assert_receive {:test_outbound_leg_connect, worker, _request, _}, 2_000

    duplicates =
      1..4
      |> Task.async_stream(fn _ -> post(c, %{}, "concurrent", endpoint: endpoint) end,
        max_concurrency: 4,
        timeout: 2_000
      )
      |> Enum.map(fn {:ok, response} -> response end)

    assert Enum.all?(duplicates, &(&1.status == 200))
    send(worker, :release_test_dial)
    assert Task.await(first, 2_000).status == 201
    refute_receive {:test_outbound_leg_connect, _, _, _}, 30
  end

  test "without a key each request creates and dials a different call", c do
    first = post(c, %{})
    second = post(c, %{})
    assert first.status == 201 and second.status == 201
    refute body(first)["call"]["id"] == body(second)["call"]["id"]
    assert_receive {:test_outbound_leg_connect, _, _, _}, 1_000
    assert_receive {:test_outbound_leg_connect, _, _, _}, 1_000
  end

  test "unknown submission returns its created call even after room shutdown", c do
    response = post(c, %{}, "uncertain", submission_status: :unknown)
    assert response.status == 201
    assert post(c, %{}, "uncertain").status == 200
    assert_receive {:test_outbound_leg_connect, _, _, _}, 1_000
    refute_receive {:test_outbound_leg_connect, _, _, _}, 30
  end

  test "submission failure projects failure and replay never redials", c do
    response = post(c, %{}, "failed", result: :failed)
    assert response.status == 503
    assert %{"error" => %{"code" => "outgoing_call_start_failed"}} = body(response)
    replay = post(c, %{}, "failed")
    assert replay.status == 503
    assert body(replay) == body(response)
    assert body(replay)["error"]["retryable"] == false
    assert_receive {:test_outbound_leg_connect, _, _, _}, 1_000
    refute_receive {:test_outbound_leg_connect, _, _, _}, 30
  end

  test "canceled binding closes the pending outgoing room without projecting failure or dialing",
       c do
    assert {:ok, call} =
             Calls.claim_outgoing_call(c.principal, c.published.call_spec_id, %{}, nil, c.options)

    observer = self()

    callback = fn
      :bind, [^call, incarnation] ->
        {:ok, monitor} =
          Vxpipe.CallEngine.monitor_room_completion(call.tenant_key, call.room_id, incarnation)

        send(observer, {:pending_completion, monitor})
        {:ok, :cancel, %{call | incarnation_id: incarnation}}

      operation, _arguments ->
        flunk("unexpected persistence operation after cancellation: #{operation}")
    end

    options =
      c.options
      |> Keyword.put(:call_repository, {Vxpipe.Gateway.TestAdmissionBindingRepository, callback})
      |> Keyword.put(
        :outbound_leg_connector,
        {TestOutboundLegConnector, %{owner: self(), observer: self()}}
      )

    assert {:error, :outgoing_call_start_failed} =
             Vxpipe.Gateway.OutgoingCallAdmission.start(options, call)

    assert_receive {:pending_completion, monitor}
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    refute_received {:test_outbound_leg_connect, _, _, _}
  end

  test "managed cancelled outgoing admission reserves cleanup before closing its unopened room",
       c do
    {:ok, call} =
      Calls.claim_outgoing_call(c.principal, c.published.call_spec_id, %{}, nil, c.options)

    observer = self()

    callback = fn
      :bind_managed, [^call, incarnation] ->
        send(observer, {:managed_outgoing_bound, incarnation})

        {:ok, :cancel, :new,
         %{
           call
           | incarnation_id: incarnation,
             gateway_cleanup_required: true,
             incarnation_binding_verified: true
         }}

      :complete, [binding, at] ->
        send(observer, {:managed_outgoing_completed, binding})

        {:ok,
         %{
           call
           | incarnation_id: binding.incarnation_id,
             gateway_cleanup_required: true,
             gateway_cleanup_completed_at: at
         }}
    end

    options =
      Keyword.merge(c.options,
        managed_cleanup: true,
        publication_enabled: false,
        call_repository: {Vxpipe.Gateway.TestAdmissionBindingRepository, callback},
        outbound_leg_connector: {Vxpipe.Gateway.Telephony.OutgoingLegConnector, []}
      )

    assert {:error, :outgoing_call_start_failed} =
             Vxpipe.Gateway.OutgoingCallAdmission.start(options, call)

    assert_receive {:managed_outgoing_bound, incarnation}, 1_000
    assert_receive {:managed_outgoing_completed, %{incarnation_id: ^incarnation}}, 1_000
    refute_received {:test_outbound_leg_connect, _, _, _}
  end

  test "projection failure cancels the unopened room without submitting a dial", c do
    {_module, context} = Keyword.fetch!(c.options, :call_repository)

    options =
      Keyword.put(
        c.options,
        :call_repository,
        {Vxpipe.Gateway.TestFailingOutgoingProjectionRepository, context}
      )

    response = post(%{c | options: options}, %{}, "projection-failed")
    assert response.status == 503
    assert %{"error" => %{"code" => "outgoing_call_start_failed"}} = body(response)

    assert {:ok, failed} =
             TestMemoryRepository.fetch_outgoing_by_key(
               context,
               c.tenant.key,
               "projection-failed"
             )

    id = failed.id
    assert {:ok, stored} = Calls.fetch_call(c.tenant.key, id, c.options)
    assert stored.state == :admitting
    assert stored.terminal_reason == nil
    replay = post(c, %{}, "projection-failed")
    assert replay.status == 200
    assert %{"call" => %{"id" => ^id, "state" => "admitting"}} = body(replay)
    # Registry cleanup may follow the controller reply. Observe termination
    # rather than requiring the registry's asynchronous removal to win the race.
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {c.tenant.key, stored.room_id}) do
      [] ->
        :ok

      [{authority, nil}] ->
        monitor = Process.monitor(authority)
        assert_receive {:DOWN, ^monitor, :process, ^authority, _reason}, 1_000
    end

    refute_receive {:test_outbound_leg_connect, _, _, _}, 30
  end

  test "handler failure and a bounded controller timeout clean up without dialing", c do
    source =
      source() |> put_in([:defaults, :capabilities, :model_inference, :model], "test:unavailable")

    assert {:ok, draft} = Calls.save_call_spec(c.tenant.key, source, c.options)
    assert {:ok, _} = Calls.publish_call_spec(c.tenant.key, draft.call_spec_id, 1, c.options)
    assert post(c, %{}, "handler-failed", spec: draft.call_spec_id).status == 503
    refute_receive {:test_outbound_leg_connect, _, _, _}, 30

    source = put_in(source, [:defaults, :capabilities, :model_inference, :model], "test:blocked")
    assert {:ok, draft} = Calls.save_call_spec(c.tenant.key, source, c.options)
    assert {:ok, _} = Calls.publish_call_spec(c.tenant.key, draft.call_spec_id, 1, c.options)

    response =
      post(c, %{}, "controller-timeout", spec: draft.call_spec_id, outgoing_start_timeout_ms: 100)

    assert response.status == 503

    assert %{"error" => %{"code" => "outgoing_submission_unknown", "retryable" => false}} =
             body(response)

    replay = post(c, %{}, "controller-timeout", spec: draft.call_spec_id)
    assert replay.status == 503
    assert body(replay) == body(response)

    assert_receive {:test_agent_runtime_model_preparing, preparation}, 1_000
    monitor = Process.monitor(preparation)
    assert_receive {:DOWN, ^monitor, :process, ^preparation, _}, 1_000
    refute_receive {:test_outbound_leg_connect, _, _, _}, 30
  end

  test "authentication, publication, direction and closed request shape prevent dialing", c do
    for {options, status} <-
          [[secret: nil], [secret: "invalid"], [secret: c.admin.secret]]
          |> Enum.zip([401, 401, 403]) do
      # The admin key belongs to another tenant; its own scope is checked there.
      options =
        if status == 403, do: Keyword.put(options, :tenant, c.admin.tenant_key), else: options

      assert post(c, %{}, nil, options).status == status
    end

    assert {:ok, foreign} =
             Administration.issue_api_key(
               c.admin.tenant_key,
               "Foreign calls",
               [:calls],
               c.options
             )

    assert post(c, %{}, nil, tenant: foreign.tenant_key, secret: foreign.secret).status == 404
    assert post(c, %{"number" => "+15550001001"}).status == 400
    assert post(c, %{}, "").status == 400
    assert post(c, %{"variables" => []}).status == 400
    # The request field is `variables`; the former `initial_variables` name is rejected.
    assert post(c, %{"initial_variables" => %{}}).status == 400
    assert post(c, %{}, nil, spec: "missing").status == 404
    assert {:ok, draft} = Calls.save_call_spec(c.tenant.key, source(), c.options)
    assert post(c, %{}, nil, spec: draft.call_spec_id).status == 422

    incoming =
      source()
      |> Map.delete(:outgoing_call)
      |> Map.put(:incoming_call, %{caller: "callee", handled_by: "assistant"})
      |> put_in([:participants, "callee", :connection], %{
        service: "primary-phone",
        mode: "receive",
        admission: "start_call",
        number: "+15550001000"
      })

    assert {:ok, draft} = Calls.save_call_spec(c.tenant.key, incoming, c.options)
    assert {:ok, _} = Calls.publish_call_spec(c.tenant.key, draft.call_spec_id, 1, c.options)
    assert post(c, %{}, nil, spec: draft.call_spec_id).status == 422
    refute_receive {:test_outbound_leg_connect, _, _, _}, 30
  end

  test "starts calls at /calls; the former /outgoing-calls path is gone", c do
    assert post(c, %{}, nil, path: "outgoing-calls").status == 404
    refute_receive {:test_outbound_leg_connect, _, _, _}, 30
    assert post(c, %{}).status == 201
    assert_receive {:test_outbound_leg_connect, _, _, _}, 1_000
  end

  test "a spec without a fixed number dials the request's validated to", c do
    source = update_in(source(), [:participants, "callee", :connection], &Map.delete(&1, :number))
    assert {:ok, draft} = Calls.save_call_spec(c.tenant.key, source, c.options)
    assert {:ok, _} = Calls.publish_call_spec(c.tenant.key, draft.call_spec_id, 1, c.options)
    spec = [spec: draft.call_spec_id]

    missing = post(c, %{}, nil, spec)
    assert missing.status == 422
    assert %{"error" => %{"code" => "to_required"}} = body(missing)

    for invalid <- ["555-0100", "+0123", "14155550123"] do
      response = post(c, %{"to" => invalid}, nil, spec)
      assert response.status == 422
      assert %{"error" => %{"code" => "invalid_to"}} = body(response)
    end

    assert post(c, %{"to" => 15_550_001_002}, nil, spec).status == 400
    refute_receive {:test_outbound_leg_connect, _, _, _}, 30

    response = post(c, %{"to" => "+15550001002"}, "to-key", spec)
    assert response.status == 201
    assert_receive {:test_outbound_leg_connect, _, request, _}, 1_000
    assert request.to == "+15550001002"

    {:ok, stored} = Calls.fetch_call(c.tenant.key, body(response)["call"]["id"], c.options)
    assert stored.to_number == "+15550001002"
    assert stored.from_number == "+15550001000"
    refute response.resp_body =~ "+15550001002"

    conflict = post(c, %{"to" => "+15550001003"}, "to-key", spec)
    assert conflict.status == 409
    refute_receive {:test_outbound_leg_connect, _, _, _}, 30
  end

  test "a spec with a fixed number rejects to and records its numbers", c do
    response = post(c, %{"to" => "+15550001002"})
    assert response.status == 422
    assert %{"error" => %{"code" => "to_not_allowed"}} = body(response)
    refute_receive {:test_outbound_leg_connect, _, _, _}, 30

    response = post(c, %{})
    assert response.status == 201
    {:ok, stored} = Calls.fetch_call(c.tenant.key, body(response)["call"]["id"], c.options)
    assert stored.to_number == "+15550001001"
    assert stored.from_number == "+15550001000"
  end

  defp mcp_endpoint(c, options) do
    admission = start_supervised!({Vxpipe.Gateway.MCP.Admission, name: nil})

    mcp = [
      enabled: true,
      allowed_hosts: ["localhost"],
      admission: admission,
      authentication: {Vxpipe.Gateway.MCP.Authentication, c.options},
      call_creation_timeout: Keyword.fetch!(options, :call_creation_timeout)
    ]

    configured = endpoint(c, Keyword.put(options, :mcp, mcp))

    initialized =
      mcp_request(c, configured, nil, %{
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: %{
          protocolVersion: "2025-11-25",
          capabilities: %{},
          clientInfo: %{name: "outgoing-test", version: "1"}
        }
      })

    assert initialized.status == 200
    [session] = get_resp_header(initialized, "mcp-session-id")
    on_exit(fn -> ExMCP.SessionManager.terminate_session(session) end)
    # Initialization is not the slow operation under test. Accelerate ordinary
    # callback deadlines after that handshake while retaining the configured
    # creation deadline.
    configured = put_in(configured, [:mcp, :protocol, :handler_call_timeout], 25)
    {configured, session}
  end

  defp mcp_tool(c, configured, session, id, name, arguments),
    do:
      mcp_request(c, configured, session, %{
        jsonrpc: "2.0",
        id: id,
        method: "tools/call",
        params: %{name: name, arguments: arguments}
      })

  defp mcp_request(c, configured, session, request) do
    connection =
      conn(:post, "https://localhost/mcp", JSON.encode!(request))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer " <> c.key.secret)
      |> put_req_header("mcp-protocol-version", "2025-11-25")

    connection =
      if session, do: put_req_header(connection, "mcp-session-id", session), else: connection

    Endpoint.call(connection, configured)
  end

  defp endpoint(c, options) do
    observer = Keyword.get(options, :observer, c.observer)

    connector =
      {TestOutboundLegConnector,
       Map.new(options) |> Map.merge(%{owner: observer, observer: observer})}

    Endpoint.init(
      mcp: Keyword.get(options, :mcp, []),
      call_admission: [
        enabled: true,
        browser_auth: Keyword.get(options, :browser_auth),
        backend:
          {CallAdmission,
           Keyword.merge(c.options, [
             {:outbound_leg_connector, connector}
             | Keyword.take(options, [:outgoing_start_timeout_ms])
           ])}
      ],
      cors: [allowed_origins: ["https://client.example.test"]]
    )
  end

  defp post(c, input, key \\ nil, options \\ []) do
    url =
      "/api/tenants/#{Keyword.get(options, :tenant, c.tenant.key)}/call-specs/#{Keyword.get(options, :spec, c.published.call_spec_id)}/#{Keyword.get(options, :path, "calls")}"

    connection =
      conn(:post, url, JSON.encode!(input))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("origin", "https://client.example.test")

    secret = Keyword.get(options, :secret, c.key.secret)

    connection =
      if secret,
        do: put_req_header(connection, "authorization", "Bearer " <> secret),
        else: connection

    connection =
      if is_nil(key), do: connection, else: put_req_header(connection, "idempotency-key", key)

    Endpoint.call(
      connection,
      Keyword.get_lazy(options, :endpoint, fn -> endpoint(c, options) end)
    )
  end

  defp body(response), do: JSON.decode!(response.resp_body)

  defp source do
    %{
      schema_version: "20261004.01",
      name: "Outgoing HTTP",
      outgoing_call: %{callee: "callee", handled_by: "assistant", ring_timeout_ms: 5_000},
      defaults: %{
        capabilities: %{model_inference: %{provider: "fixture", model: "test:scripted"}}
      },
      call_variables: %{
        sections: %{
          "data" => %{
            schema: %{
              type: "object",
              properties: %{"private" => %{type: "string"}},
              additionalProperties: false
            }
          }
        }
      },
      participants: %{
        "callee" => %{
          type: "human",
          connection: %{service: "primary-phone", mode: "dial", number: "+15550001001"}
        },
        "assistant" => %{type: "agent", prompt: "Help the callee.", tools: %{}, transfers: []}
      }
    }
  end
end
