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

  alias Vxpipe.Persistence.{ArchiveStore, EctoStorage, Repo, TestBillingLookup, UsageStore}

  alias Vxpipe.Persistence.Schema.{
    Call,
    CallSpec,
    CallSpecRevision,
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

  test "real timed-out STS recognition persists its own provider, rate and failed outcome",
       context do
    alias Vxpipe.CallEngine.Capability.SpeechToSpeech
    alias Vxpipe.CallEngine.Speech.PrivateInit
    alias Vxpipe.CallEngine.TestAudioOutputSink

    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    {:ok, private} = PrivateInit.open([], 5_000)
    {:ok, stt_private} = PrivateInit.open([], 5_000)

    tree =
      start_supervised!(
        {SpeechToSpeech.Tree,
         owner: self(),
         agent_id: "participant-agent",
         human_id: "participant-human",
         provider: {Vxpipe.Providers.MorseCode.STSSession, [output_transcript: false]},
         provider_private: private,
         output_stt: {Vxpipe.CallEngine.SpeechOutputSTTStallingProvider, []},
         output_stt_private: stt_private,
         output_stt_timeout_ms: 100,
         sink: sink,
         frame_identity: %{},
         caller_source: :sts,
         policy: nil,
         usage_context: %{
           tenant_id: @tenant_key,
           call_id: @call_id,
           room_id: @room_id,
           incarnation_id: @incarnation_id,
           participant_id: "participant-agent",
           activation_id: "activation-sts"
         }}
      )

    capability = SpeechToSpeech.Tree.capability(tree)
    assert_receive {:vxpipe_sts_ready, ^capability}, 5_000
    assert :ok = SpeechToSpeech.push_text(capability, "ONE")
    assert_receive {:test_audio_output_finish, ^sink, _}, 5_000
    :ok = TestAudioOutputSink.playback_progress(sink, 20, 1_020)
    :ok = TestAudioOutputSink.playback_completed(sink)
    assert_receive {:vxpipe_sts_turn_completed, ^capability, _, _}, 2_000
    assert_receive {:vxpipe_usage_observations, ^capability, observations}

    for {observation, sequence} <- Enum.with_index(observations, 1) do
      fact = engine_fact(observation, sequence)
      assert :ok = EctoStorage.write(context.options, fact)
      assert {:ok, archived} = ArchiveStore.fetch_call_facts(Repo, @tenant_key, @call_id)
      stored_fact = Enum.find(archived, &(&1.id == fact.id))
      assert DateTime.compare(stored_fact.occurred_at, fact.occurred_at) == :eq
      assert stored_fact.occurred_at.microsecond == fact.occurred_at.microsecond
      assert :ok = EctoStorage.write(context.options, fact)
    end

    assert {:ok, persisted} = UsageStore.fetch_usage_observations(Repo, @tenant_key, @call_id)
    assert length(persisted) == 2
    stt = Enum.find(persisted, &(&1.capability == :output_speech_to_text))
    sts = Enum.find(persisted, &(&1.capability == :speech_to_speech))
    assert sts.outcome == :succeeded
    assert stt.provider.name == "stalling_stt"
    assert stt.provider.model == "stalling_stt"
    assert stt.outcome == :failed
    assert stt.measurement.quantity == 6_300
    assert stt.measurement.unit == :milliseconds
    assert stt.measurement.provenance == :locally_measured

    assert {:ok, report} =
             Vxpipe.Calls.fetch_usage_report(context.principal, @call_id, context.options)

    stt_amount = Enum.find(report.amounts, &(&1.capability == :output_speech_to_text))
    assert stt_amount.quantity == 6_300
    assert stt_amount.provider.name == "stalling_stt"
    assert Repo.aggregate(UsageObservation, :count) == 2
  end

  test "delayed billing enrichment commits after call end and cannot revive a purged call",
       context do
    source = observation("usage-before-end", "model-attempt-ended", 160, 1, :final)

    assert {:ok, ^source} = Vxpipe.Calls.store_usage_observation(source, context.options)

    billing_observed_at = DateTime.add(@observed_at, 120, :second)

    {:ok, lookup_result} =
      Vxpipe.Calls.BillingLookupResult.new(
        delivery_id: "provider-bill-ended-v1",
        amount: "0.0046",
        currency: "USD",
        status: :final,
        observed_at: billing_observed_at
      )

    release_ref = make_ref()
    test_pid = self()
    task_supervisor = start_supervised!({Task.Supervisor, []})

    task =
      Task.Supervisor.async_nolink(task_supervisor, fn ->
        Vxpipe.Calls.enrich_usage_billing(
          context.principal,
          @call_id,
          Keyword.put(
            context.options,
            :billing_lookup,
            {TestBillingLookup,
             %{
               owner: test_pid,
               release_ref: release_ref,
               response: {:ok, lookup_result}
             }}
          )
        )
      end)

    assert_receive {:billing_lookup_started, lookup_pid, request}
    assert request.provider.request_id == "provider-request-model-attempt-ended"

    ended_at = DateTime.add(@observed_at, 60, :second)

    context.call
    |> Call.changeset(%{state: :ended, ended_at: ended_at})
    |> Repo.update!()

    send(lookup_pid, {:release_billing_lookup, release_ref})

    assert {:ok, %{stored_count: 1}} = Task.await(task)

    persisted_call = Repo.get!(Call, context.call.id)
    assert persisted_call.state == :ended
    assert persisted_call.ended_at == ended_at

    assert {:ok, %UsageReport{} = report} =
             Vxpipe.Calls.fetch_usage_report(context.principal, @call_id, context.options)

    assert Enum.any?(report.amounts, fn amount ->
             amount.provenance == :billing_lookup and amount.unit == {:currency, "USD"} and
               Decimal.equal?(amount.quantity, Decimal.new("0.0046"))
           end)

    Repo.delete!(persisted_call)

    assert {:error, :call_not_found} =
             Vxpipe.Calls.enrich_usage_billing(
               context.principal,
               @call_id,
               Keyword.put(
                 context.options,
                 :billing_lookup,
                 {TestBillingLookup,
                  %{
                    owner: self(),
                    release_ref: make_ref(),
                    response: {:ok, lookup_result}
                  }}
               )
             )

    refute_receive {:billing_lookup_started, _lookup_pid, _request}
    assert Repo.aggregate(Call, :count) == 0
    assert Repo.aggregate(UsageObservation, :count) == 0
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

    call_spec =
      %CallSpec{}
      |> CallSpec.changeset(%{tenant_id: tenant.id, public_id: "usage-call-spec"})
      |> Repo.insert!()

    revision =
      %CallSpecRevision{}
      |> CallSpecRevision.changeset(%{
        call_spec_id: call_spec.id,
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
      call_spec_revision_id: revision.id,
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
