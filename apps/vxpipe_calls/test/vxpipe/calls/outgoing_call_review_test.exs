defmodule Vxpipe.Calls.OutgoingCallReviewTest do
  @moduledoc """
  Reproductions from the 2026-10-06 outgoing-call review
  (docs/milestones/outgoing-call-review-fixes.md). Each test states the
  specified behavior and failed when written.
  """

  use ExUnit.Case, async: true

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, TestMemoryRepository, TestTelephonyServiceRepository}

  setup do
    repository = start_supervised!(TestMemoryRepository)

    options = [
      credential_repository: {TestMemoryRepository, repository},
      call_spec_repository: {TestMemoryRepository, repository},
      call_repository: {TestMemoryRepository, repository},
      registries: %{host_tools: %{}}
    ]

    assert {:ok, tenant, key} = Administration.bootstrap_tenant("Review", [:calls], options)
    assert {:ok, principal} = Calls.authenticate(tenant.key, key.secret, :calls, options)

    # The fixture's "primary-phone" service has no outbound (caller ID) number.
    options =
      Keyword.put(
        options,
        :telephony_service_repository,
        without_number(TestTelephonyServiceRepository.repository([tenant]))
      )

    %{tenant: tenant, principal: principal, options: options}
  end

  # Issue 3: the gateway dialer refuses a service without an outbound number
  # (OutgoingLegDialer), so every request for this spec fails at dial time with a
  # retryable 503. Admission must refuse it up front instead.
  test "an outgoing spec whose service has no outbound number cannot be published", c do
    assert {:ok, draft} = Calls.save_call_spec(c.tenant.key, source(), c.options)

    assert {:error, _reason} =
             Calls.publish_call_spec(c.tenant.key, draft.call_spec_id, 1, c.options)
  end

  # Issue 4: the outgoing API creates no route or join token for a human handler, so
  # the callee would answer into a room nobody can join.
  test "an outgoing spec cannot name a human participant as handled_by", c do
    source =
      put_in(source(), [:participants, "assistant"], %{
        type: "human",
        connection: %{service: "web", mode: "receive", admission: "start_call"}
      })

    assert {:error, _reason} = Calls.save_call_spec(c.tenant.key, source, c.options)
  end

  test "removing caller ID after publication prevents a new claim", c do
    {module, bindings} = Keyword.fetch!(c.options, :telephony_service_repository)

    valid =
      Map.new(bindings, fn {key, snapshot} ->
        {key, %{snapshot | service: %{snapshot.service | outbound_number: "+15550001001"}}}
      end)

    options = Keyword.put(c.options, :telephony_service_repository, {module, valid})
    assert {:ok, draft} = Calls.save_call_spec(c.tenant.key, source(), options)
    assert {:ok, _} = Calls.publish_call_spec(c.tenant.key, draft.call_spec_id, 1, options)

    assert {:error, error} =
             Calls.claim_outgoing_call(c.principal, draft.call_spec_id, %{}, nil, c.options)

    assert error.code == :provider_credential_unavailable
    assert error.details["path"] == ["participants", "callee", "connection", "service"]
  end

  defp without_number({module, bindings}) do
    {module,
     Map.new(bindings, fn {key, snapshot} ->
       {key, %{snapshot | service: %{snapshot.service | outbound_number: nil}}}
     end)}
  end

  defp source do
    %{
      schema_version: "20261004.01",
      name: "Outgoing review",
      outgoing_call: %{callee: "callee", handled_by: "assistant", ring_timeout_ms: 5_000},
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
      participants: %{
        "callee" => %{
          type: "human",
          connection: %{service: "primary-phone", mode: "dial", number: "+15550001000"}
        },
        "assistant" => %{type: "agent", prompt: "Help the callee.", tools: %{}, transfers: []}
      }
    }
  end
end
