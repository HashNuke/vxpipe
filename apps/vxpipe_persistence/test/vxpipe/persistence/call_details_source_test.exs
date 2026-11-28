defmodule Vxpipe.Persistence.CallDetailsSourceTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.CallEngine.Usage.{Attribution, Measurement, Observation, ProviderContext}

  alias Vxpipe.Calls

  alias Vxpipe.Calls.{
    Administration,
    CallArtifact,
    CallDetailsAssessment,
    CallFact,
    VariableSnapshot
  }

  alias Vxpipe.Persistence.{
    ArchiveStore,
    ArtifactStore,
    CallDetailsSource,
    CallDetailsPublicationStore,
    CallStore,
    CredentialStore,
    CallSpecStore,
    Repo,
    TestPublicationArtifactWriter,
    TestPublicationClock,
    UsageStore
  }

  alias Vxpipe.Persistence.Schema.{Call, CallDetailsPublication}

  @tenant_key "DETAILSSOURCE001"
  @call_id "11111111-2222-4333-8444-555555555555"
  @room_id "66666666-7777-4888-8999-000000000000"
  @incarnation_id "rinc-call-details-source"
  @created_at ~U[2026-09-12 21:00:00.000000Z]
  @started_at ~U[2026-09-12 21:00:05.000000Z]
  @ended_at ~U[2026-09-12 21:01:00.000000Z]

  setup do
    options = repository_options()

    assert {:ok, tenant, issued_key} =
             Administration.bootstrap_tenant("Call details source", [:calls], options)

    assert {:ok, principal} =
             Administration.authenticate(tenant.key, issued_key.secret, :calls, options)

    assert {:ok, draft} = Calls.save_call_spec(tenant.key, call_spec(), options)

    assert {:ok, published} =
             Calls.publish_call_spec(tenant.key, draft.call_spec_id, 1, options)

    route = Enum.find(published.routes, &(&1.participant_ref == "caller"))

    options =
      Keyword.merge(options,
        now: @created_at,
        call_id_generator: fn -> @call_id end,
        room_id_generator: fn -> @room_id end,
        actor_id_generator: fn -> "77777777-8888-4999-8aaa-bbbbbbbbbbbb" end,
        token_id_generator: fn -> "cccccccc-dddd-4eee-8fff-000000000000" end,
        join_token_generator: fn -> "vxj_test-only-call-details-source" end
      )

    assert {:ok, call, token} =
             Calls.prepare_call(principal, route.key, initial_variables(), options)

    scope = %{tenant_key: tenant.key, call_id: call.id, participant_key: route.key}
    assert {:ok, claim} = Calls.claim_join_token(token.secret, scope, options)
    assert {:ok, running} = Calls.mark_call_started(claim, @incarnation_id, @started_at, options)

    [call: running, options: options, principal: principal, tenant: tenant]
  end

  test "reads one complete permitted publication source from a coherent persisted snapshot",
       context do
    archive_variables(context)
    observation = model_observation(context, "turn-1", "attempt-1")
    assert {:ok, ^observation} = Calls.store_usage_observation(observation, context.options)
    archive_recording(context)
    archive_history(context)

    source_options = [repo: Repo, recording: :configured]

    assert {:ok, %CallDetailsAssessment{} = assessment} =
             CallDetailsSource.read(source_options, @tenant_key, @call_id)

    source = assessment.source
    components = Map.new(assessment.components, &{&1.name, &1.status})

    assert assessment.ended_at == @ended_at

    assert source.call["identity"] == %{
             "call_id" => @call_id,
             "call_spec_id" => context.call.call_spec_id,
             "call_spec_revision" => 1,
             "call_spec_schema_version" => "20260915.01",
             "plan_digest" => "sha256:" <> Base.encode16(context.call.plan_digest, case: :lower),
             "tenant_key" => @tenant_key
           }

    assert source.call["lifecycle"]["state"] == "ended"
    assert source.call["lifecycle"]["direction"] == "inbound"
    assert source.call["lifecycle"]["ended_at"] == "2026-09-12T21:01:00.000000Z"
    assert source.call["lifecycle"]["terminal_reason"] == nil
    assert source.call["lifecycle"]["route"]["participant"] == "caller"
    assert source.call["lifecycle"]["route"]["service"] == "web"

    assert Enum.map(source.participants, & &1["call_spec_key"]) == ["assistant", "caller"]

    assistant = Enum.find(source.participants, &(&1["call_spec_key"] == "assistant"))
    assert assistant["type"] == "agent"

    assert assistant["activation_ids"] == [
             context.call.plan.participants["assistant"].activation_id
           ]

    refute Map.has_key?(assistant, "prompt")

    assert Enum.map(source.transcript, & &1["kind"]) == [
             "accepted_input",
             "agent_output_generated",
             "agent_output_delivered"
           ]

    assert Enum.at(source.transcript, 0)["payload"]["content"] == "Hello"
    assert Enum.at(source.transcript, 1)["payload"]["text"] == "Welcome"
    assert Enum.map(source.tools, & &1["kind"]) == ["tool_call_started", "tool_call_completed"]

    assert Enum.map(source.transfers, & &1["kind"]) == [
             "participant_transfer_started",
             "participant_transfer_completed"
           ]

    assert source.variables["latest_revision"] == 1
    assert source.variables["sections"] == %{"order" => %{"id" => "ORD-2"}}
    assert Enum.map(source.variables["history"], & &1["revision"]) == [0, 1]

    assert [%{"capability" => "model_inference", "outcome" => "succeeded"}] =
             Enum.map(source.usage["observations"], &Map.take(&1, ["capability", "outcome"]))

    assert [%{"component" => "input_tokens", "quantity" => 12, "unit" => "tokens"}] =
             Enum.map(
               source.usage["amounts"],
               &Map.take(&1, ["component", "quantity", "unit"])
             )

    assert [%{"kind" => "full_mix", "object_key" => "calls/test/recording.s16le"}] =
             Enum.map(source.artifacts, &Map.take(&1, ["kind", "object_key"]))

    assert components == %{
             "history" => :complete,
             "recording" => :complete,
             "usage" => :complete,
             "variables" => :complete
           }

    assert {:error, :call_not_found} =
             CallDetailsSource.read(source_options, "OTHERDETAILS0001", @call_id)
  end

  test "keeps configured absent recording pending and distinguishes unconfigured recording",
       context do
    archive_variables(context)
    archive_history(context)

    assert {:ok, configured} =
             CallDetailsSource.read([repo: Repo, recording: :configured], @tenant_key, @call_id)

    assert component_status(configured, "recording") == :pending
    assert component_status(configured, "usage") == :not_produced

    assert {:ok, unconfigured} =
             CallDetailsSource.read([repo: Repo, recording: :unconfigured], @tenant_key, @call_id)

    assert component_status(unconfigured, "recording") == :unconfigured
  end

  test "call details expose recovery timing on the affected caller", context do
    caller = context.call.plan.participants["caller"]
    payload = %{"phase" => "hearing_completed", "elapsed_ms" => 1732}

    item =
      fact(context, 1, :caller_speech_recovery,
        participant_id: caller.participant_id,
        payload: payload
      )

    assert {:ok, ^item} = Calls.archive_call_fact(item, context.options)

    closure =
      fact(context, 2, :archive_stream_closed,
        occurred_at: @ended_at,
        payload: %{"accepted" => 1, "incomplete" => false}
      )

    assert {:ok, ^closure} = Calls.archive_call_fact(closure, context.options)

    assert {:ok, assessment} =
             CallDetailsSource.read([repo: Repo, recording: :unconfigured], @tenant_key, @call_id)

    participant = Enum.find(assessment.source.participants, &(&1["call_spec_key"] == "caller"))
    assert [%{"kind" => "caller_speech_recovery", "payload" => ^payload}] = participant["events"]
  end

  test "round-trips mixed message formats and trusted columns into deterministic publications",
       context do
    assistant = context.call.plan.participants["assistant"]

    content = %{
      "type" => "participant_message",
      "participant_id" => assistant.participant_id,
      "agent_mode" => "listener",
      "message" => "嗯，okay"
    }

    payload = %{
      "content_format" => "structured_agent_message_v1",
      "content" => content,
      "aggregated_by" => "sentence",
      "will_be_spoken" => true
    }

    output =
      fact(context, 2, :agent_output_generated,
        participant_id: assistant.participant_id,
        activation_id: assistant.activation_id,
        source_participant_id: "trusted-source",
        connection_id: "connection-typed",
        command_id: "command-typed",
        correlation_id: "correlation-typed",
        payload: payload
      )

    legacy =
      fact(context, 1, :accepted_input,
        participant_id: "trusted-source",
        payload: %{"content" => "{\"message\":\"literal\"}"}
      )

    tool =
      fact(context, 3, :tool_call_completed,
        tool_call_id: "native-tool",
        participant_id: assistant.participant_id,
        payload: %{"result" => %{"message" => "unchanged", "status" => "running"}}
      )

    closure =
      fact(context, 4, :archive_stream_closed,
        occurred_at: @ended_at,
        payload: %{"accepted" => 3, "incomplete" => false}
      )

    for item <- [legacy, output, tool, output, closure] do
      assert {:ok, ^item} = Calls.archive_call_fact(item, context.options)
    end

    assert {:ok, facts} = ArchiveStore.fetch_call_facts(Repo, @tenant_key, @call_id)
    assert facts == [legacy, output, tool, closure]
    assert {:ok, history} = Calls.fetch_call_history(context.principal, @call_id, context.options)
    assert history.transcript == [legacy, output]
    assert history.tool_history == [tool]

    assert {:ok, assessment} =
             CallDetailsSource.read([repo: Repo, recording: :unconfigured], @tenant_key, @call_id)

    [published_legacy, published_output] = assessment.source.transcript
    assert published_legacy["payload"] == legacy.payload
    assert published_output["payload"] == payload

    for field <- [
          :participant_id,
          :activation_id,
          :source_participant_id,
          :connection_id,
          :command_id,
          :correlation_id,
          :public_sequence,
          :sequence
        ] do
      assert published_output[Atom.to_string(field)] == Map.fetch!(output, field)
    end

    assert hd(assessment.source.tools)["payload"] == tool.payload

    time = DateTime.add(@ended_at, 60, :second)

    assert {:ok, decision} =
             Vxpipe.Calls.PublicationWindow.evaluate(@ended_at, time, assessment.components)

    assert {:ok, first} =
             Vxpipe.Calls.CallDetailsSnapshot.new(
               "mixed-publication",
               time,
               assessment.source,
               decision
             )

    reordered = %{
      assessment.source
      | transcript: [
          published_legacy,
          %{published_output | "payload" => Map.new(Enum.reverse(payload))}
        ]
    }

    assert {:ok, replay} =
             Vxpipe.Calls.CallDetailsSnapshot.new("mixed-publication", time, reordered, decision)

    assert first.contents == replay.contents
    assert first.source_digest == replay.source_digest
    assert first.checksum == replay.checksum
    document = JSON.decode!(first.contents)
    assert document["schema_version"] == "20260912.01"
    assert Enum.at(document["transcript"], 1)["payload"] == payload
  end

  test "downloaded Decisions evidence requires permission at the source interval", context do
    alias Vxpipe.Persistence.Schema.CallFact, as: StoredFact
    call = Repo.get_by!(Call, public_id: @call_id)

    # Model older stored records that bypass today's write-time sanitizer.
    for {interval, ordinal} <- Enum.with_index([true, false, nil]) do
      policy = if is_nil(interval), do: %{}, else: %{"save_transcripts" => interval}

      Repo.insert!(%StoredFact{
        public_id: "question-#{ordinal}",
        call_id: call.id,
        room_id: @room_id,
        incarnation_id: @incarnation_id,
        kind: "decisions_question_result",
        sequence: 20 + ordinal,
        occurred_at: @started_at,
        participant_id: context.call.plan.participants["assistant"].participant_id,
        source_policy: policy,
        payload: %{
          "evaluation_id" => "evaluation",
          "question_id" => "rule_#{ordinal}",
          "ordinal" => ordinal,
          "required_answer" => "yes",
          "threshold_hundredths" => 70,
          "probability_yes" => 0.2,
          "inferred_answer" => "no",
          "outcome" => "failed",
          "policy_revision" => 1,
          "policy_digest" => "sha256:" <> String.duplicate("a", 64),
          "question" => "Private question #{ordinal}?",
          "feedback" => "Private response #{ordinal}.",
          "feedback_origin" => "authored",
          "feedback_dispatched" => true
        }
      })
    end

    options = publication_options(context)

    archive_history(%{context | options: options})
    assert_receive {:vxpipe_call_details_published, _, publication_id, 1}, 2_000

    assert {:ok, doc} =
             Calls.fetch_call_details(context.principal, @call_id, publication_id, options)

    assert doc.contents =~ "Private response 0."
    refute doc.contents =~ "Private response 1."
    refute doc.contents =~ "Private response 2."
    refute doc.contents =~ "Private question 1?"
    refute doc.contents =~ "Private question 2?"

    assert {:error, :insufficient_scope} =
             Calls.fetch_call_details(
               %{context.principal | scopes: MapSet.new()},
               @call_id,
               publication_id,
               options
             )

    assert {:error, _} =
             Calls.fetch_call_details(
               %{context.principal | tenant_key: "OTHER01234567890"},
               @call_id,
               publication_id,
               options
             )
  end

  test "Decisions attempts and pinned outcomes survive SQL replay and document publication",
       context do
    alias Vxpipe.CallEngine.Usage.Settlement
    alias Vxpipe.Persistence.{EctoStorage, TestDecisionsHistoryFixture}

    rewrite = model_observation(context, "output-turn", "output-turn:2")
    facts = TestDecisionsHistoryFixture.facts(context.call, rewrite)
    first_usage = Enum.find(facts, &(&1.kind == :usage_observed))

    assert {:error, :interrupted} =
             Repo.transaction(fn ->
               assert :ok = EctoStorage.write(context.options, first_usage)
               Repo.rollback(:interrupted)
             end)

    assert {:ok, []} = UsageStore.fetch_usage_observations(Repo, @tenant_key, @call_id)

    # Replay the same private archive deliveries. Both the fact IDs and the
    # usage delivery IDs must survive this round trip without double charging.
    for _delivery <- 1..2, item <- facts do
      assert :ok = EctoStorage.write(context.options, item)
    end

    assert {:ok, stored_facts} = ArchiveStore.fetch_call_facts(Repo, @tenant_key, @call_id)
    assert Enum.map(stored_facts, & &1.id) == Enum.map(facts, & &1.id)
    denied = Enum.find(stored_facts, &(&1.id == "input:permitted"))
    assert denied.payload["content_unavailable"] == %{"reason" => "denied"}
    refute Map.has_key?(denied.payload, "question")

    assert {:ok, observations} = UsageStore.fetch_usage_observations(Repo, @tenant_key, @call_id)
    assert {:ok, settlement} = Settlement.derive(observations)
    assert {:ok, amounts} = UsageStore.fetch_usage_amounts(Repo, @tenant_key, @call_id)
    assert MapSet.new(settlement.amounts) == MapSet.new(amounts)
    assert {:ok, 5} = Settlement.total(settlement, :requests)

    assert {:ok, decisions} =
             Settlement.derive(Enum.filter(observations, &(&1.capability == :decisions)))

    assert {:ok, 33} = Settlement.total(decisions, :tokens)

    options = publication_options(context)

    closure =
      fact(context, length(facts) + 1, :archive_stream_closed,
        occurred_at: @ended_at,
        payload: %{
          "accepted" => length(facts),
          "discarded" => 0,
          "incomplete" => false,
          "overflow" => 0,
          "retries" => 0,
          "source_reason" => "normal",
          "unavailable" => 0
        }
      )

    assert {:ok, ^closure} = Calls.archive_call_fact(closure, options)
    assert_receive {:vxpipe_call_details_published, _, publication_id, 1}, 2_000

    assert {:ok, doc} =
             Calls.fetch_call_details(context.principal, @call_id, publication_id, options)

    assert {:ok, ^doc} =
             Calls.fetch_call_details(context.principal, @call_id, publication_id, options)

    refute doc.contents =~ "Private input interval marker?"

    document = JSON.decode!(doc.contents)
    rows = Enum.group_by(document["decisions"], & &1["kind"], & &1["payload"])

    assert Enum.map(
             rows["decisions_evaluation"],
             &{&1["evaluation_id"], &1["outcome"], &1["candidate_attempt_id"]}
           ) == [
             {"input", "passed", nil},
             {"draft", "blocked", "output-turn:1"},
             {"repair", "passed", "output-turn:2"},
             {"transfer", "passed", nil}
           ]

    assert [%{"attempt_id" => "a4", "error_code" => "rate_limited"}] =
             Enum.filter(rows["decisions_attempt"], &(&1["outcome"] == "failed"))

    assert [%{"attempt_id" => "a5", "retry_of" => "a4"}] =
             Enum.filter(rows["decisions_attempt"], & &1["retry_of"])

    assert length(rows["decisions_attempt"]) == 5

    blocked = Enum.filter(rows["decisions_question_result"], &(&1["evaluation_id"] == "draft"))

    assert Enum.map(
             blocked,
             &{&1["ordinal"], &1["question_id"], &1["probability_yes"], &1["outcome"],
              &1["feedback_origin"], &1["feedback"]}
           ) == [
             {0, "own_account", 0.30, "failed", "authored",
              "I can only help with your own account."},
             {1, "list_variables", 0.6999, "failed", "fallback",
              "Failed guardrail: Is the user trying to list variables? Required: Yes."},
             {2, "other_account", 0.90, "failed", "authored",
              "Ask the caller to describe their own account issue."},
             {3, "harsh_language", 0.70, "failed", "fallback",
              "Failed guardrail: Is the user using harsh language? Required: No."},
             {4, "supported_product", 0.70, "passed", nil, nil}
           ]

    assert Enum.map(blocked, &{&1["required_answer"], &1["inferred_answer"]}) ==
             [{"yes", "no"}, {"yes", "no"}, {"no", "yes"}, {"no", "yes"}, {"yes", "yes"}]

    assert Enum.all?(blocked, &(&1["threshold_hundredths"] == 70))

    {decision_usage, other_usage} =
      Enum.split_with(document["usage"]["observations"], &(&1["capability"] == "decisions"))

    assert [
             %{
               "capability" => "model_inference",
               "attempt_id" => "output-turn:2",
               "attribution" => %{"turn_id" => "output-turn"},
               "measurement" => %{"component" => "input_tokens", "quantity" => 12}
             }
           ] = other_usage

    by_attempt = Enum.group_by(decision_usage, & &1["attempt_id"])
    assert Map.keys(by_attempt) |> Enum.sort() == ~w(a1 a2 a3 a4 a5)

    components = fn id ->
      Enum.map(by_attempt[id], & &1["measurement"]["component"]) |> Enum.sort()
    end

    assert components.("a2") == ["input_tokens", "requests"]
    assert components.("a3") == ["output_tokens", "requests", "total_tokens"]
    assert components.("a4") == ["requests"]

    for {attempt, turn, invocation} <- [
          {"a1", "input-turn", nil},
          {"a2", "output-turn", nil},
          {"a3", "output-turn", nil},
          {"a4", nil, "handoff"},
          {"a5", nil, "handoff"}
        ],
        row <- by_attempt[attempt] do
      assert %{"name" => "openai", "model" => "test-decisions"} = row["provider"]
      assert row["attribution"]["turn_id"] == turn
      assert row["attribution"]["tool_call_id"] == invocation
    end

    for private_detail <- [
          "Failed guardrail:",
          "I can only help",
          "Is the request about",
          "probability_yes"
        ] do
      refute JSON.encode!(document["usage"]) =~ private_detail
    end

    assert {:error, :insufficient_scope} =
             Calls.fetch_call_details(
               %{context.principal | scopes: MapSet.new()},
               @call_id,
               publication_id,
               options
             )

    foreign = %{context.principal | tenant_key: "OTHER01234567890"}
    assert {:error, :call_not_found} = Calls.fetch_usage_report(foreign, @call_id, options)

    assert {:error, :call_details_not_found} =
             Calls.fetch_call_details(foreign, @call_id, publication_id, options)
  end

  test "late reported tokens settle once and preserve the cancelled evaluation", context do
    alias Vxpipe.Persistence.{EctoStorage, TestDecisionsHistoryFixture}
    {initial, late} = TestDecisionsHistoryFixture.cancelled_with_late_tokens(context.call)

    for item <- initial, do: assert(:ok = EctoStorage.write(context.options, item))
    assert {:ok, original} = ArchiveStore.fetch_call_facts(Repo, @tenant_key, @call_id)

    assert {:ok, [%{component: "requests", quantity: 1}]} =
             UsageStore.fetch_usage_amounts(Repo, @tenant_key, @call_id)

    assert :ok = EctoStorage.write(context.options, late)
    assert :ok = EctoStorage.write(context.options, late)

    assert {:discard, :call_fact_conflict} =
             EctoStorage.write(context.options, %{
               late
               | occurred_at: DateTime.add(late.occurred_at, 1, :microsecond)
             })

    assert {:discard, :call_fact_conflict} =
             EctoStorage.write(context.options, %{
               late
               | payload: Map.put(late.payload, "outcome", "failed")
             })

    assert {:ok, replay} = ArchiveStore.fetch_call_facts(Repo, @tenant_key, @call_id)

    assert Enum.reject(replay, &(&1.kind == :usage_observed)) ==
             Enum.reject(original, &(&1.kind == :usage_observed))

    assert {:ok, amounts} = UsageStore.fetch_usage_amounts(Repo, @tenant_key, @call_id)

    assert [%{attempt_id: "cancelled-attempt", quantity: 42, status: :correction}] =
             Enum.filter(amounts, &(&1.component == "total_tokens"))

    assert [%{payload: %{"outcome" => "cancelled"}}] =
             Enum.filter(replay, &(&1.kind == :decisions_evaluation))
  end

  test "publishes at the deadline and refreshes after late recording metadata", context do
    clock = start_supervised!({Agent, fn -> DateTime.add(@ended_at, 60, :second) end})

    publication_options =
      Keyword.merge(context.options,
        publication_enabled: true,
        publication_source: {CallDetailsSource, [repo: Repo, recording: :configured]},
        publication_repository: {CallDetailsPublicationStore, Repo},
        publication_artifact_writer:
          {TestPublicationArtifactWriter, %{observer: self(), clock: clock}},
        publication_clock: {TestPublicationClock, clock},
        maximum_attempts: 1,
        observer: self()
      )

    archive_variables(context)
    archive_history(%{context | options: publication_options})

    assert_receive {:vxpipe_call_details_published, _worker, first_id, 1}, 1_000

    [first] = Repo.all(CallDetailsPublication)
    assert first.public_id == first_id
    assert first.completeness == :incomplete
    assert first.status == :published

    Agent.update(clock, fn _time -> DateTime.add(@ended_at, 61, :second) end)
    archive_recording(%{context | options: publication_options})

    assert_receive {:vxpipe_call_details_published, _worker, second_id, 1}, 1_000
    refute second_id == first_id

    publications =
      CallDetailsPublication
      |> Repo.all()
      |> Enum.sort_by(& &1.recorded_at, DateTime)

    assert [persisted_first, persisted_second] = publications
    assert persisted_first.completeness == :incomplete
    assert persisted_second.completeness == :complete
    assert persisted_first.source_digest != persisted_second.source_digest
    assert persisted_first.filename != persisted_second.filename

    call = Call |> Repo.get_by!(public_id: @call_id) |> Repo.preload(:latest_details_publication)
    assert call.latest_details_publication.public_id == second_id
  end

  defp publication_options(context) do
    alias Vxpipe.Persistence.CallDetailsInspectionStore
    clock = start_supervised!({Agent, fn -> DateTime.add(@ended_at, 60, :second) end})

    Keyword.merge(context.options,
      publication_enabled: true,
      publication_source: {CallDetailsSource, [repo: Repo, recording: :configured]},
      publication_repository: {CallDetailsPublicationStore, Repo},
      publication_artifact_writer:
        {TestPublicationArtifactWriter, %{observer: self(), clock: clock}},
      publication_clock: {TestPublicationClock, clock},
      maximum_attempts: 1,
      observer: self(),
      call_details_inspection_repository: {CallDetailsInspectionStore, Repo}
    )
  end

  defp archive_history(context) do
    assistant = context.call.plan.participants["assistant"]
    caller = context.call.plan.participants["caller"]

    facts = [
      fact(context, 1, :participant_joined, participant_id: caller.participant_id),
      fact(context, 2, :accepted_input,
        participant_id: caller.participant_id,
        source_participant_id: caller.participant_id,
        payload: %{"content" => "Hello", "modality" => "text"}
      ),
      fact(context, 3, :agent_output_generated,
        participant_id: assistant.participant_id,
        activation_id: assistant.activation_id,
        payload: %{"text" => "Welcome"}
      ),
      fact(context, 4, :agent_output_delivered,
        participant_id: assistant.participant_id,
        activation_id: assistant.activation_id,
        payload: %{"delivery" => "complete"}
      ),
      fact(context, 5, :tool_call_started,
        participant_id: assistant.participant_id,
        activation_id: assistant.activation_id,
        tool_call_id: "tool-1",
        payload: %{"name" => "lookup", "arguments" => %{"order_id" => "ORD-1"}}
      ),
      fact(context, 6, :tool_call_completed,
        participant_id: assistant.participant_id,
        activation_id: assistant.activation_id,
        tool_call_id: "tool-1",
        payload: %{"result" => %{"status" => "found"}}
      ),
      fact(context, 7, :participant_transfer_started,
        participant_id: assistant.participant_id,
        activation_id: assistant.activation_id,
        payload: %{"destination" => "caller"}
      ),
      fact(context, 8, :participant_transfer_completed,
        participant_id: assistant.participant_id,
        activation_id: assistant.activation_id,
        payload: %{"destination" => "caller"}
      )
    ]

    Enum.each(facts, fn fact ->
      assert {:ok, ^fact} = Calls.archive_call_fact(fact, context.options)
    end)

    closure =
      fact(context, 9, :archive_stream_closed,
        occurred_at: @ended_at,
        payload: %{
          "accepted" => 8,
          "discarded" => 0,
          "incomplete" => false,
          "overflow" => 0,
          "retries" => 0,
          "source_reason" => "normal",
          "unavailable" => 0
        }
      )

    assert {:ok, ^closure} = Calls.archive_call_fact(closure, context.options)
  end

  defp archive_variables(context) do
    baseline =
      variable_snapshot(context, "variables-0", :baseline, 0, %{
        "order" => %{revision: 0, value: %{"id" => "ORD-1"}}
      })

    update =
      variable_snapshot(context, "variables-1", :update, 1, %{
        "order" => %{revision: 1, value: %{"id" => "ORD-2"}}
      })

    assert {:ok, ^baseline} = Calls.archive_variable_snapshot(baseline, context.options)
    assert {:ok, ^update} = Calls.archive_variable_snapshot(update, context.options)
  end

  defp model_observation(context, turn_id, attempt_id) do
    assistant = context.call.plan.participants["assistant"]

    assert {:ok, provider} = ProviderContext.new(name: "fixture", model: "test-model")

    assert {:ok, attribution} =
             Attribution.new(
               room_id: @room_id,
               incarnation_id: @incarnation_id,
               participant_id: assistant.participant_id,
               activation_id: assistant.activation_id,
               turn_id: turn_id
             )

    assert {:ok, measurement} =
             Measurement.new(
               component: "input_tokens",
               unit: :tokens,
               quantity: 12,
               mode: :delta,
               status: :final,
               provenance: :provider_reported
             )

    assert {:ok, observation} =
             Observation.new(
               id: "usage-1",
               tenant_id: @tenant_key,
               call_id: @call_id,
               attempt_id: attempt_id,
               capability: :model_inference,
               provider: provider,
               attribution: attribution,
               measurement: measurement,
               outcome: :succeeded,
               observed_at: DateTime.add(@started_at, 4, :second)
             )

    observation
  end

  defp archive_recording(context) do
    assert {:ok, artifact} =
             CallArtifact.new(
               id: "artifact-1",
               tenant_key: @tenant_key,
               call_id: @call_id,
               room_id: @room_id,
               incarnation_id: @incarnation_id,
               kind: :full_mix,
               object_key: "calls/test/recording.s16le",
               object_reference: %{
                 "object_key" => "calls/test/recording.s16le",
                 "etag" => "etag-1"
               },
               sample_rate: 16_000,
               channels: 1,
               sample_format: :s16le,
               started_offset_samples: 0,
               ended_offset_samples: 320,
               sample_count: 320,
               accepted_chunks: 1,
               rejected_chunks: 0,
               gaps: [],
               status: :complete,
               terminal_reason: "normal"
             )

    assert {:ok, ^artifact} = Calls.archive_call_artifact(artifact, context.options)
  end

  defp variable_snapshot(_context, id, :baseline, revision, sections) do
    assert {:ok, snapshot} =
             VariableSnapshot.new(
               id: id,
               kind: :baseline,
               tenant_key: @tenant_key,
               call_id: @call_id,
               room_id: @room_id,
               incarnation_id: @incarnation_id,
               global_revision: revision,
               sections: sections,
               source_policy: %{"revision" => 0},
               occurred_at: @started_at
             )

    snapshot
  end

  defp variable_snapshot(context, id, :update, revision, sections) do
    assistant = context.call.plan.participants["assistant"]

    assert {:ok, snapshot} =
             VariableSnapshot.new(
               id: id,
               kind: :update,
               tenant_key: @tenant_key,
               call_id: @call_id,
               room_id: @room_id,
               incarnation_id: @incarnation_id,
               global_revision: revision,
               sections: sections,
               source_policy: %{"revision" => 0},
               occurred_at: DateTime.add(@started_at, 3, :second),
               command_id: "command-variables",
               participant_id: assistant.participant_id,
               activation_id: assistant.activation_id,
               source_participant_id: assistant.participant_id,
               correlation_id: "turn-variables",
               tool_call_id: "tool-variables",
               section: "order",
               section_revision: 1
             )

    snapshot
  end

  defp fact(_context, sequence, kind, overrides) do
    defaults = [
      id: "fact-#{sequence}",
      kind: kind,
      sequence: sequence,
      tenant_key: @tenant_key,
      call_id: @call_id,
      room_id: @room_id,
      incarnation_id: @incarnation_id,
      participant_id: nil,
      activation_id: nil,
      source_participant_id: nil,
      connection_id: nil,
      command_id: "command-#{sequence}",
      correlation_id: "turn-1",
      tool_call_id: nil,
      public_sequence: sequence,
      occurred_at: DateTime.add(@started_at, sequence, :second),
      source_policy: %{"revision" => 0, "save_transcripts" => true},
      payload: %{}
    ]

    assert {:ok, fact} = CallFact.new(Keyword.merge(defaults, overrides))
    fact
  end

  defp component_status(assessment, name) do
    assessment.components
    |> Enum.find(&(&1.name == name))
    |> then(& &1.status)
  end

  defp repository_options do
    [
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      archive_repository: {ArchiveStore, Repo},
      artifact_repository: {ArtifactStore, Repo},
      usage_repository: {UsageStore, Repo},
      tenant_key_generator: fn -> @tenant_key end,
      uuid_generator:
        sequence([
          "aaaaaaaa-1111-4111-8111-111111111111",
          "bbbbbbbb-2222-4222-8222-222222222222",
          "cccccccc-3333-4333-8333-333333333333"
        ]),
      api_key_generator: fn -> "vxp_test-only-call-details-source" end,
      registries: %{
        host_tools: %{}
      }
    ]
  end

  defp call_spec do
    %{
      schema_version: "20260915.01",
      name: "Support call",
      entry_caller: "caller",
      entry_receiver: "assistant",
      media_policy: %{record_audio: true},
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
      call_variables: %{
        sections: %{
          "order" => %{
            schema: %{
              "type" => "object",
              "properties" => %{"id" => %{"type" => "string"}},
              "additionalProperties" => false
            }
          }
        }
      },
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Help the caller without exposing this prompt.",
          first_message: %{mode: "wait_for_input"},
          variable_permissions: %{"order" => ["read", "write"]},
          tools: %{},
          transfers: []
        }
      }
    }
  end

  defp initial_variables, do: %{"order" => %{"id" => "ORD-1"}}

  defp sequence(values) do
    key = {__MODULE__, make_ref()}
    Process.put(key, values)

    fn ->
      [value | rest] = Process.get(key)
      Process.put(key, rest)
      value
    end
  end
end
