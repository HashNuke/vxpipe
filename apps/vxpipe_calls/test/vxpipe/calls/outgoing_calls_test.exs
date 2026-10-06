defmodule Vxpipe.Calls.OutgoingCallsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Calls

  alias Vxpipe.Calls.{
    Administration,
    Principal,
    TestMemoryRepository,
    TestTelephonyServiceRepository
  }

  setup do
    repository = start_supervised!(TestMemoryRepository)

    options = [
      credential_repository: {TestMemoryRepository, repository},
      call_spec_repository: {TestMemoryRepository, repository},
      call_repository: {TestMemoryRepository, repository},
      registries: %{host_tools: %{}}
    ]

    assert {:ok, tenant, key} = Administration.bootstrap_tenant("Outgoing", [:calls], options)
    assert {:ok, principal} = Calls.authenticate(tenant.key, key.secret, :calls, options)

    options =
      Keyword.put(
        options,
        :telephony_service_repository,
        TestTelephonyServiceRepository.repository([tenant])
      )

    assert {:ok, draft} = Calls.save_call_spec(tenant.key, source(), options)
    assert {:ok, published} = Calls.publish_call_spec(tenant.key, draft.call_spec_id, 1, options)
    %{principal: principal, options: options, published: published, repository: repository}
  end

  test "records room start once and preserves the first failure", c do
    assert {:ok, call} =
             Calls.claim_outgoing_call(c.principal, c.published.call_spec_id, %{}, nil, c.options)

    started = DateTime.utc_now()

    assert {:ok, running} =
             Calls.mark_outgoing_call_started(call, "rinc-outgoing", started, c.options)

    assert running.state == :running
    assert running.started_at == started

    assert {:ok, ^running} =
             Calls.mark_outgoing_call_started(
               call,
               "rinc-outgoing",
               DateTime.add(started, 1, :second),
               c.options
             )

    assert {:error, :outgoing_start_conflict} =
             Calls.mark_outgoing_call_started(call, "different-room", started, c.options)

    assert {:ok, failed} = Calls.mark_outgoing_call_failed(call, :room_start_failed, c.options)
    assert failed.state == :failed
    assert failed.started_at == started
    assert failed.terminal_reason == :room_start_failed
    assert {:ok, ^failed} = Calls.mark_outgoing_call_failed(call, :startup_unknown, c.options)
  end

  test "claims the published outgoing plan without a join token", c do
    assert {:ok, call} =
             Calls.claim_outgoing_call(c.principal, c.published.call_spec_id, %{}, nil, c.options)

    assert call.state == :admitting
    assert call.plan.direction == :outgoing
    assert call.call_spec_revision == 1
    assert call.idempotency_key == nil
    assert call.idempotency_digest == nil
    assert call.participant_routes == %{}
    assert TestMemoryRepository.admissions(c.repository) == []
    assert {:ok, ^call} = Calls.fetch_call(c.principal.tenant_key, call.id, c.options)
  end

  test "requires calls scope and tenant ownership before insertion", c do
    %Principal{} = principal = c.principal
    admin = %{principal | scopes: MapSet.new([:admin])}

    assert {:error, :not_authorized} =
             Calls.claim_outgoing_call(admin, c.published.call_spec_id, %{}, nil, c.options)

    foreign = %{principal | tenant_key: "foreign-tenant"}

    assert {:error, :not_found} =
             Calls.claim_outgoing_call(foreign, c.published.call_spec_id, %{}, nil, c.options)
  end

  test "draft-only and incoming specs cannot create an outgoing call", c do
    assert {:ok, draft} = Calls.save_call_spec(c.principal.tenant_key, source(), c.options)

    assert {:error, :call_spec_not_published} =
             Calls.claim_outgoing_call(c.principal, draft.call_spec_id, %{}, nil, c.options)

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

    assert {:ok, draft} = Calls.save_call_spec(c.principal.tenant_key, incoming, c.options)

    assert {:ok, _published} =
             Calls.publish_call_spec(c.principal.tenant_key, draft.call_spec_id, 1, c.options)

    assert {:error, :call_spec_not_outgoing} =
             Calls.claim_outgoing_call(c.principal, draft.call_spec_id, %{}, nil, c.options)
  end

  test "uses the publication pointer rather than the latest draft or largest revision", c do
    options = Keyword.put(c.options, :call_spec_id, c.published.call_spec_id)
    assert {:ok, second} = Calls.save_call_spec(c.principal.tenant_key, source(), options)
    assert second.revision == 2

    assert {:ok, call} =
             Calls.claim_outgoing_call(c.principal, second.call_spec_id, %{}, nil, c.options)

    assert call.call_spec_revision == 1

    assert {:ok, _second} =
             Calls.publish_call_spec(c.principal.tenant_key, second.call_spec_id, 2, c.options)

    assert {:ok, _first} =
             Calls.publish_call_spec(c.principal.tenant_key, second.call_spec_id, 1, c.options)

    assert {:ok, call} =
             Calls.claim_outgoing_call(c.principal, second.call_spec_id, %{}, nil, c.options)

    assert call.call_spec_revision == 1
  end

  test "a canonical same-key replay returns the original while changes conflict", c do
    variables = %{"data" => %{"a" => "one", "b" => "two"}}

    assert {:ok, first} =
             Calls.claim_outgoing_call(
               c.principal,
               c.published.call_spec_id,
               variables,
               "retry-key",
               c.options
             )

    assert {:duplicate, ^first} =
             Calls.claim_outgoing_call(
               c.principal,
               c.published.call_spec_id,
               %{"data" => Map.new([{"b", "two"}, {"a", "one"}])},
               "retry-key",
               c.options
             )

    assert {:error, :idempotency_conflict} =
             Calls.claim_outgoing_call(
               c.principal,
               c.published.call_spec_id,
               %{"data" => %{"a" => "changed"}},
               "retry-key",
               c.options
             )

    refute inspect(first) =~ "retry-key"

    for key <- ["", String.duplicate("x", 257), 42] do
      assert {:error, :invalid_idempotency_key} =
               Calls.claim_outgoing_call(
                 c.principal,
                 c.published.call_spec_id,
                 %{},
                 key,
                 c.options
               )
    end
  end

  test "concurrent same-key requests have one winner and one original call", c do
    results =
      1..8
      |> Task.async_stream(
        fn _ ->
          Calls.claim_outgoing_call(
            c.principal,
            c.published.call_spec_id,
            %{},
            "concurrent",
            c.options
          )
        end,
        max_concurrency: 8,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert [{:ok, first}] = Enum.filter(results, &match?({:ok, _}, &1))
    assert Enum.count(results, &(&1 == {:duplicate, first})) == 7
  end

  defp source do
    %{
      schema_version: "20261004.01",
      name: "Outgoing",
      outgoing_call: %{callee: "callee", handled_by: "assistant", ring_timeout_ms: 5_000},
      call_variables: %{
        sections: %{
          "data" => %{
            schema: %{
              type: "object",
              properties: %{"a" => %{type: "string"}, "b" => %{type: "string"}},
              additionalProperties: false
            }
          }
        }
      },
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
