defmodule Vxpipe.Calls.BillingEnrichmentTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Usage.{Attribution, Measurement, Observation, ProviderContext}

  alias Vxpipe.Calls.{
    BillingEnrichmentReport,
    BillingLookupResult,
    Principal,
    TestBillingLookup,
    TestUsageRepository
  }

  @tenant_key "BILLINGTENANT001"
  @call_id "call-billing-1"
  @observed_at ~U[2026-09-12 14:00:00.000000Z]
  @lookup_at ~U[2026-09-12 14:05:00.000000Z]

  setup do
    repository =
      start_supervised!(
        {TestUsageRepository,
         tenant_key: @tenant_key,
         call_id: @call_id,
         observations: [
           observation("usage-total", "total_tokens", nil),
           observation("usage-input", "input_tokens", "total_tokens", request_id: nil)
         ]}
      )

    principal = %Principal{
      tenant_key: @tenant_key,
      api_key_id: "api-key-billing",
      scopes: MapSet.new([:calls])
    }

    [repository: repository, principal: principal]
  end

  test "stores one delayed lookup result for one persisted provider attempt", context do
    release_ref = make_ref()

    lookup =
      {TestBillingLookup,
       %{
         owner: self(),
         release_ref: release_ref,
         response: fn _request ->
           BillingLookupResult.new(
             delivery_id: "provider-bill-version-1",
             amount: "0.0046",
             currency: "USD",
             status: :final,
             observed_at: @lookup_at
           )
         end
       }}

    task_supervisor = start_supervised!({Task.Supervisor, []})

    task =
      Task.Supervisor.async_nolink(task_supervisor, fn ->
        Vxpipe.Calls.enrich_usage_billing(
          context.principal,
          @call_id,
          usage_repository: TestUsageRepository.repository(context.repository),
          billing_lookup: lookup
        )
      end)

    assert_receive {:billing_lookup_started, lookup_pid, request}
    assert request.tenant_key == @tenant_key
    assert request.call_id == @call_id
    assert request.attempt_id == "model-attempt-1"
    assert request.capability == :model_inference
    assert request.provider.name == "provider-fixture"
    assert request.provider.integration_id == "model-primary"
    assert request.provider.request_id == "provider-request-1"
    assert request.attribution.turn_id == "turn-1"
    refute inspect(request) =~ "provider-request-1"

    send(lookup_pid, {:release_billing_lookup, release_ref})

    assert {:ok,
            %BillingEnrichmentReport{
              candidate_count: 1,
              lookup_count: 1,
              stored_count: 1,
              pending_count: 0,
              unsupported_count: 0,
              unavailable_count: 0,
              missing_reference_count: 0
            }} = Task.await(task)

    assert [_total, _input, cost] = TestUsageRepository.observations(context.repository)
    assert cost.attempt_id == "model-attempt-1"
    assert cost.provider == request.provider
    assert cost.attribution == request.attribution
    assert cost.delivery_id == "provider-bill-version-1"
    assert cost.source_sequence == nil
    assert cost.outcome == :succeeded
    assert cost.observed_at == @lookup_at
    assert cost.measurement.component == "cost"
    assert cost.measurement.unit == {:currency, "USD"}
    assert Decimal.equal?(cost.measurement.quantity, Decimal.new("0.0046"))
    assert cost.measurement.mode == :cumulative
    assert cost.measurement.status == :final
    assert cost.measurement.provenance == :billing_lookup
  end

  test "repeating the same provider billing delivery is idempotent", context do
    lookup =
      {TestBillingLookup,
       %{
         owner: self(),
         response:
           BillingLookupResult.new(
             delivery_id: "provider-bill-version-1",
             amount: "0.0046",
             currency: "USD",
             status: :final,
             observed_at: @lookup_at
           )
       }}

    options = [
      usage_repository: TestUsageRepository.repository(context.repository),
      billing_lookup: lookup
    ]

    assert {:ok, %BillingEnrichmentReport{stored_count: 1}} =
             Vxpipe.Calls.enrich_usage_billing(context.principal, @call_id, options)

    assert_receive {:billing_lookup_started, _lookup_pid, _request}

    assert {:ok, %BillingEnrichmentReport{stored_count: 1}} =
             Vxpipe.Calls.enrich_usage_billing(context.principal, @call_id, options)

    assert_receive {:billing_lookup_started, _lookup_pid, _request}
    assert length(TestUsageRepository.observations(context.repository)) == 3
  end

  test "keeps pending, unsupported, unavailable, and missing-reference outcomes distinct",
       context do
    observations = [
      observation("usage-pending", "total_tokens", nil,
        attempt_id: "attempt-pending",
        provider_name: "provider-pending",
        request_id: "request-pending"
      ),
      observation("usage-unsupported", "total_tokens", nil,
        attempt_id: "attempt-unsupported",
        provider_name: "provider-unsupported",
        request_id: "request-unsupported"
      ),
      observation("usage-unavailable", "total_tokens", nil,
        attempt_id: "attempt-unavailable",
        provider_name: "provider-unavailable",
        request_id: "request-unavailable"
      ),
      observation("usage-missing", "total_tokens", nil,
        attempt_id: "attempt-missing",
        provider_name: "provider-missing",
        request_id: nil
      ),
      observation("usage-conflict-1", "total_tokens", nil,
        attempt_id: "attempt-conflict",
        provider_name: "provider-conflict",
        request_id: "request-conflict-1"
      ),
      observation("usage-conflict-2", "input_tokens", "total_tokens",
        attempt_id: "attempt-conflict",
        provider_name: "provider-conflict",
        request_id: "request-conflict-2"
      )
    ]

    repository =
      start_supervised!(
        {TestUsageRepository,
         tenant_key: @tenant_key, call_id: @call_id, observations: observations},
        id: :outcome_usage_repository
      )

    response = fn request ->
      case request.provider.name do
        "provider-pending" -> {:ok, :pending}
        "provider-unsupported" -> {:error, :unsupported}
        "provider-unavailable" -> {:error, :credentials_unavailable}
      end
    end

    assert {:ok,
            %BillingEnrichmentReport{
              candidate_count: 5,
              lookup_count: 3,
              stored_count: 0,
              pending_count: 1,
              unsupported_count: 1,
              unavailable_count: 2,
              missing_reference_count: 1
            }} =
             Vxpipe.Calls.enrich_usage_billing(
               context.principal,
               @call_id,
               usage_repository: TestUsageRepository.repository(repository),
               billing_lookup: {TestBillingLookup, %{owner: self(), response: response}}
             )

    for _index <- 1..3 do
      assert_receive {:billing_lookup_started, _lookup_pid, _request}
    end

    refute_receive {:billing_lookup_started, _lookup_pid, _request}
  end

  test "treats an omitted lookup port as unsupported without inventing a price", context do
    assert {:ok,
            %BillingEnrichmentReport{
              candidate_count: 1,
              lookup_count: 0,
              stored_count: 0,
              unsupported_count: 1
            }} =
             Vxpipe.Calls.enrich_usage_billing(
               context.principal,
               @call_id,
               usage_repository: TestUsageRepository.repository(context.repository)
             )

    assert length(TestUsageRepository.observations(context.repository)) == 2
  end

  test "reports a bounded lookup timeout as unavailable", context do
    release_ref = make_ref()

    assert {:ok,
            %BillingEnrichmentReport{
              lookup_count: 1,
              stored_count: 0,
              unavailable_count: 1
            }} =
             Vxpipe.Calls.enrich_usage_billing(
               context.principal,
               @call_id,
               usage_repository: TestUsageRepository.repository(context.repository),
               billing_lookup:
                 {TestBillingLookup,
                  %{owner: self(), release_ref: release_ref, response: {:ok, :pending}}},
               billing_lookup_timeout: 100
             )

    assert_receive {:billing_lookup_started, _lookup_pid, _request}
  end

  test "does not report enrichment when the observation commit fails", context do
    :ok = TestUsageRepository.reject_stores(context.repository, :database_unavailable)

    lookup =
      {TestBillingLookup,
       %{
         owner: self(),
         response:
           BillingLookupResult.new(
             delivery_id: "provider-bill-version-1",
             amount: "0.0046",
             currency: "USD",
             status: :final,
             observed_at: @lookup_at
           )
       }}

    assert {:error, :database_unavailable} =
             Vxpipe.Calls.enrich_usage_billing(
               context.principal,
               @call_id,
               usage_repository: TestUsageRepository.repository(context.repository),
               billing_lookup: lookup
             )

    assert_receive {:billing_lookup_started, _lookup_pid, _request}
    assert length(TestUsageRepository.observations(context.repository)) == 2
  end

  test "rejects a principal without calls scope before lookup", context do
    principal = %{context.principal | scopes: MapSet.new([:admin])}

    assert {:error, :insufficient_scope} =
             Vxpipe.Calls.enrich_usage_billing(
               principal,
               @call_id,
               usage_repository: TestUsageRepository.repository(context.repository),
               billing_lookup: {TestBillingLookup, %{owner: self(), response: {:ok, :pending}}}
             )

    refute_receive {:billing_lookup_started, _lookup_pid, _request}
  end

  defp observation(id, component, included_in, options \\ []) do
    {:ok, provider} =
      ProviderContext.new(
        name: Keyword.get(options, :provider_name, "provider-fixture"),
        integration_id: "model-primary",
        model: "fixture-model",
        request_id: Keyword.get(options, :request_id, "provider-request-1")
      )

    {:ok, attribution} =
      Attribution.new(
        room_id: "room-billing-1",
        incarnation_id: "incarnation-billing-1",
        participant_id: "participant-agent",
        activation_id: "activation-agent",
        turn_id: "turn-1"
      )

    {:ok, measurement} =
      Measurement.new(
        component: component,
        unit: :tokens,
        quantity: 10,
        mode: :cumulative,
        status: :final,
        provenance: :provider_reported,
        included_in: included_in
      )

    {:ok, observation} =
      Observation.new(
        id: id,
        tenant_id: @tenant_key,
        call_id: @call_id,
        attempt_id: Keyword.get(options, :attempt_id, "model-attempt-1"),
        capability: :model_inference,
        provider: provider,
        attribution: attribution,
        measurement: measurement,
        outcome: :succeeded,
        observed_at: @observed_at
      )

    observation
  end
end
