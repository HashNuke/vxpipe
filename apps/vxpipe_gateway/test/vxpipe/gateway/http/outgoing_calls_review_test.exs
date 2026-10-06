defmodule Vxpipe.Gateway.HTTP.OutgoingCallsReviewTest do
  @moduledoc """
  Reproductions from the 2026-10-06 outgoing-call review
  (docs/milestones/outgoing-call-review-fixes.md). Each test states the
  specified behavior and failed when written.
  """

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

    assert {:ok, tenant, key} = Administration.bootstrap_tenant("Review HTTP", [:calls], options)

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

    %{options: options, tenant: tenant, key: key, published: published}
  end

  # Issue 5: a failed start answers 503 with "retryable": true, yet repeating the request
  # with the same Idempotency-Key answers 200, a success status for a call that never
  # connected. A replay must not report success for a failed attempt.
  test "replaying a failed outgoing call with the same key is not reported as success", c do
    failed = post(c, "retry-me", result: :failed)
    assert failed.status == 503
    assert %{"error" => %{"retryable" => false}} = JSON.decode!(failed.resp_body)

    replay = post(c, "retry-me")
    refute replay.status in 200..299
  end

  defp post(c, key, options \\ []) do
    connector =
      {TestOutboundLegConnector,
       Map.new(options) |> Map.merge(%{owner: self(), observer: self()})}

    endpoint =
      Endpoint.init(
        call_admission: [
          enabled: true,
          backend: {CallAdmission, Keyword.put(c.options, :outbound_leg_connector, connector)}
        ]
      )

    conn(
      :post,
      "/api/tenants/#{c.tenant.key}/call-specs/#{c.published.call_spec_id}/calls",
      JSON.encode!(%{})
    )
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer " <> c.key.secret)
    |> put_req_header("idempotency-key", key)
    |> then(&Endpoint.call(&1, endpoint))
  end

  defp source do
    %{
      schema_version: "20261004.01",
      name: "Outgoing review HTTP",
      outgoing_call: %{callee: "callee", handled_by: "assistant", ring_timeout_ms: 5_000},
      defaults: %{
        capabilities: %{model_inference: %{provider: "fixture", model: "test:scripted"}}
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
