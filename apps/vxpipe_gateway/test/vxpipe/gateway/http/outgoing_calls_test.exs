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
      key: key,
      admin: admin,
      published: published,
      observer: self()
    }
  end

  test "routes before spec writes and returns a private-free 201 after submission", c do
    response =
      post(
        c,
        %{"initial_variables" => %{"data" => %{"private" => "private-sentinel"}}},
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
      post(c, %{"initial_variables" => %{"data" => %{"private" => "changed"}}}, "idempotent")

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
    assert replay.status == 200
    assert %{"call" => %{"state" => "failed"}} = body(replay)
    assert_receive {:test_outbound_leg_connect, _, _, _}, 1_000
    refute_receive {:test_outbound_leg_connect, _, _, _}, 30
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
    replay = post(c, %{}, "projection-failed")
    assert replay.status == 200
    assert body(replay)["call"]["state"] == "failed"
    id = body(replay)["call"]["id"]
    assert {:ok, stored} = Calls.fetch_call(c.tenant.key, id, c.options)
    assert Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {c.tenant.key, stored.room_id}) == []
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
    assert post(c, %{"initial_variables" => []}).status == 400
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

  defp endpoint(c, options) do
    observer = Keyword.get(options, :observer, c.observer)

    connector =
      {TestOutboundLegConnector,
       Map.new(options) |> Map.merge(%{owner: observer, observer: observer})}

    Endpoint.init(
      call_admission: [
        enabled: true,
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
      "/api/tenants/#{Keyword.get(options, :tenant, c.tenant.key)}/call-specs/#{Keyword.get(options, :spec, c.published.call_spec_id)}/outgoing-calls"

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
