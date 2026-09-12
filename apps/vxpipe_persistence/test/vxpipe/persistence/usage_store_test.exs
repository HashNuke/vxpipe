defmodule Vxpipe.Persistence.UsageStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.CallEngine.Archive.Fact

  alias Vxpipe.CallEngine.Usage.{
    ArchiveProjection,
    Attribution,
    Measurement,
    Observation,
    ProviderContext
  }

  alias Vxpipe.Calls.{Principal, UsageReport}

  alias Vxpipe.Persistence.{ArchiveStore, EctoStorage, Repo, UsageStore}

  alias Vxpipe.Persistence.Schema.{
    Call,
    CallDefinition,
    DefinitionRevision,
    Tenant,
    UsageAmount,
    UsageObservation
  }

  alias Vxpipe.Persistence.Schema.CallFact, as: StoredCallFact

  @tenant_key "USAGEPROJECTION1"
  @call_id "11111111-2222-4333-8444-555555555555"
  @room_id "66666666-7777-4888-8999-000000000000"
  @incarnation_id "rinc-usage-persistence"
  @observed_at ~U[2026-09-12 09:00:00.000000Z]

  setup do
    call = insert_running_call()

    options = [
      archive_repository: {ArchiveStore, Repo},
      usage_repository: {UsageStore, Repo}
    ]

    principal = %Principal{
      tenant_key: @tenant_key,
      api_key_id: "api-key-usage",
      scopes: MapSet.new([:calls])
    }

    [call: call, options: options, principal: principal]
  end

  test "asynchronously stored facts maintain effective amounts and tenant-safe totals", context do
    first = observation("usage-observation-1", "model-attempt-1", 100, 1, :estimate)
    final = observation("usage-observation-2", "model-attempt-1", 160, 2, :final)
    second_attempt = observation("usage-observation-3", "model-attempt-2", 40, 1, :final)
    second_attempt_fact = engine_fact(second_attempt, 3)

    assert :ok = EctoStorage.write(context.options, engine_fact(first, 1))
    assert :ok = EctoStorage.write(context.options, engine_fact(final, 2))
    assert :ok = EctoStorage.write(context.options, second_attempt_fact)
    assert :ok = EctoStorage.write(context.options, second_attempt_fact)

    assert {:ok, %UsageReport{} = report} =
             Vxpipe.Calls.fetch_usage_report(context.principal, @call_id, context.options)

    assert length(report.amounts) == 2
    assert [total] = report.totals
    assert total.quantity == 200
    assert total.amount_count == 2
    assert total.capability == :model_inference
    assert total.participant_id == "participant-agent"
    assert total.turn_id == "turn-usage"
    assert total.unit == :tokens
    assert total.provenance == :provider_reported

    assert Enum.map(report.amounts, & &1.provider.request_id) == [
             "provider-request-model-attempt-1",
             "provider-request-model-attempt-2"
           ]

    assert Repo.aggregate(StoredCallFact, :count) == 3
    assert Repo.aggregate(UsageObservation, :count) == 3
    assert Repo.aggregate(UsageAmount, :count) == 2

    conflicting = observation("usage-observation-4", "model-attempt-2", 41, 1, :final)

    assert {:discard, :conflicting_delivery} =
             EctoStorage.write(context.options, engine_fact(conflicting, 4))

    assert Repo.aggregate(StoredCallFact, :count) == 4
    assert Repo.aggregate(UsageObservation, :count) == 3

    assert {:ok, %UsageReport{totals: [unchanged_total]}} =
             Vxpipe.Calls.fetch_usage_report(context.principal, @call_id, context.options)

    assert unchanged_total.quantity == 200

    other_tenant = %{context.principal | tenant_key: "OTHERPROJECTION2"}

    assert {:error, :call_not_found} =
             Vxpipe.Calls.fetch_usage_report(other_tenant, @call_id, context.options)

    unauthorized = %{context.principal | scopes: MapSet.new([:admin])}

    assert {:error, :insufficient_scope} =
             Vxpipe.Calls.fetch_usage_report(unauthorized, @call_id, context.options)
  end

  test "incremental included components and exact currency remain honest", context do
    input =
      observation("usage-input", "model-attempt-included", 100, 1, :final,
        component: "input_tokens",
        included_in: "total_tokens"
      )

    assert :ok = EctoStorage.write(context.options, engine_fact(input, 1))

    assert {:ok, %UsageReport{amounts: [input_amount], totals: []}} =
             Vxpipe.Calls.fetch_usage_report(context.principal, @call_id, context.options)

    assert input_amount.included_in == "total_tokens"

    total =
      observation("usage-total", "model-attempt-included", 160, 2, :final,
        component: "total_tokens"
      )

    output =
      observation("usage-output", "model-attempt-included", 60, 3, :final,
        component: "output_tokens",
        included_in: "total_tokens"
      )

    cost =
      observation("usage-cost", "billing-attempt", "0.0046", 1, :final,
        component: "cost",
        unit: {:currency, "USD"},
        provenance: :billing_lookup
      )

    assert :ok = EctoStorage.write(context.options, engine_fact(total, 2))
    assert :ok = EctoStorage.write(context.options, engine_fact(output, 3))
    assert :ok = EctoStorage.write(context.options, engine_fact(cost, 4))

    assert {:ok, %UsageReport{} = report} =
             Vxpipe.Calls.fetch_usage_report(context.principal, @call_id, context.options)

    assert Enum.map(report.amounts, & &1.component) == [
             "cost",
             "input_tokens",
             "output_tokens",
             "total_tokens"
           ]

    totals = Map.new(report.totals, &{&1.unit, &1.quantity})
    assert totals[:tokens] == 160
    assert Decimal.equal?(totals[{:currency, "USD"}], Decimal.new("0.0046"))
  end

  defp observation(id, attempt_id, quantity, source_sequence, status, options \\ []) do
    {:ok, provider} =
      ProviderContext.new(
        name: "provider-fixture",
        integration_id: "model-primary",
        model: "fixture-model",
        request_id: "provider-request-#{attempt_id}"
      )

    {:ok, attribution} =
      Attribution.new(
        room_id: @room_id,
        incarnation_id: @incarnation_id,
        participant_id: "participant-agent",
        activation_id: "activation-agent",
        turn_id: "turn-usage"
      )

    {:ok, measurement} =
      Measurement.new(
        component: Keyword.get(options, :component, "total_tokens"),
        unit: Keyword.get(options, :unit, :tokens),
        quantity: quantity,
        mode: :cumulative,
        status: status,
        provenance: Keyword.get(options, :provenance, :provider_reported),
        included_in: Keyword.get(options, :included_in)
      )

    {:ok, observation} =
      Observation.new(
        id: id,
        source_sequence: source_sequence,
        tenant_id: @tenant_key,
        call_id: @call_id,
        attempt_id: attempt_id,
        capability: :model_inference,
        provider: provider,
        attribution: attribution,
        measurement: measurement,
        outcome: :succeeded,
        observed_at: DateTime.add(@observed_at, source_sequence, :second)
      )

    observation
  end

  defp engine_fact(observation, sequence) do
    attributes =
      Keyword.merge(
        [
          kind: :usage_observed,
          sequence: sequence,
          tenant_id: @tenant_key,
          call_id: @call_id,
          room_id: @room_id,
          incarnation_id: @incarnation_id,
          source_policy: %{"revision" => 1}
        ],
        ArchiveProjection.attributes(observation)
      )

    Fact.new!(attributes)
  end

  defp insert_running_call do
    tenant =
      %Tenant{}
      |> Tenant.changeset(%{key: @tenant_key, name: "Usage projection tenant"})
      |> Repo.insert!()

    definition =
      %CallDefinition{}
      |> CallDefinition.changeset(%{tenant_id: tenant.id, public_id: "usage-definition"})
      |> Repo.insert!()

    revision =
      %DefinitionRevision{}
      |> DefinitionRevision.changeset(%{
        call_definition_id: definition.id,
        revision: 1,
        schema_version: "20260912.01",
        source: %{},
        source_digest: String.duplicate("a", 64),
        compiled_metadata: %{},
        validation_errors: []
      })
      |> Repo.insert!()

    %Call{}
    |> Call.changeset(%{
      public_id: @call_id,
      tenant_id: tenant.id,
      definition_revision_id: revision.id,
      participant_routes: %{},
      entry_caller: "caller",
      entry_receiver: "assistant",
      initial_variables: %{},
      resolved_plan: :erlang.term_to_binary(%{}),
      plan_digest: :crypto.hash(:sha256, "usage-plan"),
      state: :running,
      room_id: @room_id,
      incarnation_id: @incarnation_id,
      created_at: @observed_at,
      started_at: @observed_at
    })
    |> Repo.insert!()
  end
end
