defmodule Vxpipe.Persistence.CallStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  import Ecto.Query

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, VariableSnapshot}
  alias Vxpipe.CallEngine.Archive.{Fact, Handoff}
  alias Vxpipe.CallEngine.Archive.Supervisor, as: ArchiveSupervisor
  alias Vxpipe.CallEngine.CallVariables.{BaselineSnapshot, UpdateSnapshot}

  alias Vxpipe.Persistence.{
    ArchiveStore,
    CallStore,
    CredentialStore,
    DefinitionStore,
    EctoStorage,
    InspectionStore,
    Repo
  }

  alias Vxpipe.Persistence.Schema.Admission, as: StoredAdmission
  alias Vxpipe.Persistence.Schema.Call, as: StoredCall
  alias Vxpipe.Persistence.Schema.JoinToken, as: StoredJoinToken
  alias Vxpipe.Persistence.Schema.CallFact, as: StoredCallFact
  alias Vxpipe.Persistence.Schema.VariableSnapshot, as: StoredVariableSnapshot

  @tenant_key "AAAAAAAAAAAAAAAA"
  @key_id "11111111-1111-4111-8111-111111111111"
  @definition_id "22222222-2222-4222-8222-222222222222"
  @route_id "33333333-3333-4333-8333-333333333333"
  @support_route_id "34343434-3434-4434-8434-343434343434"
  @call_id "44444444-4444-4444-8444-444444444444"
  @room_id "55555555-5555-4555-8555-555555555555"
  @actor_id "66666666-6666-4666-8666-666666666666"
  @token_id "77777777-7777-4777-8777-777777777777"
  @api_key "vxp_test-only-call-store-key"
  @join_token "vxj_test-only-persisted-token"
  @now ~U[2026-09-09 11:00:00.000000Z]

  setup do
    repository_options = [
      credential_repository: {CredentialStore, Repo},
      definition_repository: {DefinitionStore, Repo},
      call_repository: {CallStore, Repo},
      archive_repository: {ArchiveStore, Repo},
      inspection_repository: {InspectionStore, Repo},
      tenant_key_generator: fn -> @tenant_key end,
      uuid_generator: sequence([@key_id, @definition_id, @route_id, @support_route_id]),
      api_key_generator: fn -> @api_key end,
      registries: registries()
    ]

    assert {:ok, tenant, issued_key} =
             Administration.bootstrap_tenant("Stored calls", [:calls], repository_options)

    assert {:ok, principal} =
             Administration.authenticate(
               tenant.key,
               issued_key.secret,
               :calls,
               repository_options
             )

    assert {:ok, draft} =
             Calls.save_definition(tenant.key, definition_input(), repository_options)

    assert {:ok, published} =
             Calls.publish_definition(tenant.key, draft.definition_id, 1, repository_options)

    assert route = Enum.find(published.routes, &(&1.participant_ref == "caller"))
    assert support_route = Enum.find(published.routes, &(&1.participant_ref == "support"))

    options =
      repository_options ++
        [
          now: @now,
          call_id_generator: fn -> @call_id end,
          room_id_generator: fn -> @room_id end,
          actor_id_generator: fn -> @actor_id end,
          token_id_generator: fn -> @token_id end,
          join_token_generator: fn -> @join_token end
        ]

    [
      options: options,
      principal: principal,
      route: route,
      support_route: support_route,
      tenant: tenant
    ]
  end

  test "atomically stores and reconstructs a private prepared call and its first token",
       context do
    variables = %{"order" => %{"id" => "ORD-2048"}}

    assert {:ok, prepared, issued} =
             Calls.prepare_call(context.principal, context.route.key, variables, context.options)

    assert prepared.id == @call_id
    assert prepared.started_at == nil
    assert prepared.plan.call_variables.sections["order"].value == variables["order"]

    assert %StoredCall{} = stored_call = Repo.get_by!(StoredCall, public_id: @call_id)
    assert stored_call.state == :prepared
    assert stored_call.initial_variables == variables
    assert stored_call.started_at == nil
    assert is_binary(stored_call.resolved_plan)
    refute inspect(stored_call) =~ "ORD-2048"

    assert %StoredJoinToken{} =
             stored_token =
             Repo.get_by!(StoredJoinToken, public_id: @token_id)

    assert stored_token.digest == :crypto.hash(:sha256, issued.secret)
    assert stored_token.consumed_at == nil
    refute Map.has_key?(Map.from_struct(stored_token), :secret)
    refute inspect(stored_token) =~ issued.secret

    assert {:ok, reloaded} = Calls.fetch_call(context.tenant.key, @call_id, context.options)
    assert reloaded.initial_variables == variables
    assert reloaded.plan == prepared.plan
    assert reloaded.plan_digest == prepared.plan_digest
    assert Repo.aggregate(StoredCall, :count) == 1
    assert Repo.aggregate(StoredJoinToken, :count) == 1
  end

  test "lists persisted calls through the bounded inspection adapter", context do
    assert {:ok, first, _token} = prepare(context)

    later_options =
      Keyword.merge(context.options,
        now: DateTime.add(@now, 30, :second),
        call_id_generator: fn -> "88888888-8888-4888-8888-888888888888" end,
        room_id_generator: fn -> "99999999-9999-4999-8999-999999999999" end,
        actor_id_generator: fn -> "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" end,
        token_id_generator: fn -> "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" end,
        join_token_generator: fn -> "vxj_test-only-inspection-token" end
      )

    assert {:ok, second, _token} =
             Calls.prepare_call(
               context.principal,
               context.route.key,
               %{"order" => %{"id" => "must-not-appear-in-summary"}},
               later_options
             )

    assert {:ok, first_page} = Calls.list_calls(context.principal, context.options ++ [limit: 1])
    assert [summary] = first_page.calls
    assert summary.id == second.id
    assert summary.definition_id == second.definition_id
    assert summary.definition_revision == second.definition_revision
    assert summary.state == :prepared
    assert summary.created_at == DateTime.add(@now, 30, :second)
    refute inspect(summary) =~ "must-not-appear-in-summary"
    assert is_binary(first_page.next_cursor)

    assert {:ok, second_page} =
             Calls.list_calls(
               context.principal,
               context.options ++ [limit: 1, cursor: first_page.next_cursor]
             )

    assert Enum.map(second_page.calls, & &1.id) == [first.id]
    assert second_page.next_cursor == nil

    other_tenant = %{context.principal | tenant_key: "ZZZZZZZZZZZZZZZZ"}
    assert {:ok, empty} = Calls.list_calls(other_tenant, context.options)
    assert empty.calls == []
  end

  test "rolls back the call when its first token cannot be stored", context do
    assert {:ok, _first_call, _first_token} = prepare(context)

    second_options =
      Keyword.merge(context.options,
        call_id_generator: fn -> "88888888-8888-4888-8888-888888888888" end,
        room_id_generator: fn -> "99999999-9999-4999-8999-999999999999" end,
        actor_id_generator: fn -> "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" end,
        token_id_generator: fn -> "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" end
      )

    assert {:error, :join_token_conflict} =
             Calls.prepare_call(context.principal, context.route.key, %{}, second_options)

    assert Repo.aggregate(StoredCall, :count) == 1
    assert Repo.aggregate(StoredJoinToken, :count) == 1
  end

  test "atomically accepts only one of two tokens for the same participant", context do
    assert {:ok, call, first} = prepare(context)

    second_options =
      Keyword.merge(context.options,
        token_id_generator: fn -> "cccccccc-cccc-4ccc-8ccc-cccccccccccc" end,
        join_token_generator: fn -> "vxj_test-only-second-persisted-token" end
      )

    assert {:ok, second} =
             Calls.issue_join_token(
               context.principal,
               call.id,
               context.route.key,
               second_options
             )

    scope = scope(context, call)

    results =
      [first.secret, second.secret]
      |> Task.async_stream(
        &Calls.claim_join_token(&1, scope, context.options),
        max_concurrency: 2,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _claim}, &1)) == 1

    assert Enum.count(
             results,
             &match?({:error, :participant_admission_unavailable}, &1)
           ) == 1

    assert Repo.aggregate(StoredAdmission, :count) == 1

    assert Repo.aggregate(
             from(token in StoredJoinToken, where: not is_nil(token.consumed_at)),
             :count
           ) == 1

    assert Repo.get_by!(StoredCall, public_id: call.id).state == :admitting
  end

  test "consumes one token once when the same token races itself", context do
    assert {:ok, call, token} = prepare(context)
    scope = scope(context, call)

    results =
      1..2
      |> Task.async_stream(
        fn _attempt -> Calls.claim_join_token(token.secret, scope, context.options) end,
        max_concurrency: 2,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _claim}, &1)) == 1
    assert Enum.count(results, &match?({:error, :token_already_claimed}, &1)) == 1
    assert Repo.aggregate(StoredAdmission, :count) == 1
  end

  test "keeps an expired token unused and accepts an issued token after key revocation",
       context do
    assert {:ok, call, expired} = prepare(context)
    scope = scope(context, call)
    later = Keyword.put(context.options, :now, DateTime.add(@now, 301, :second))

    assert {:error, :token_expired} = Calls.claim_join_token(expired.secret, scope, later)
    assert Repo.get_by!(StoredJoinToken, public_id: expired.id).consumed_at == nil
    assert Repo.get_by!(StoredCall, public_id: call.id).state == :prepared

    fresh_options =
      Keyword.merge(later,
        token_id_generator: fn -> "dddddddd-dddd-4ddd-8ddd-dddddddddddd" end,
        join_token_generator: fn -> "vxj_test-only-post-revocation-token" end
      )

    assert {:ok, fresh} =
             Calls.issue_join_token(
               context.principal,
               call.id,
               context.route.key,
               fresh_options
             )

    assert {:ok, _revoked} =
             Administration.revoke_api_key(
               context.tenant.key,
               context.principal.api_key_id,
               later
             )

    assert {:ok, claim} = Calls.claim_join_token(fresh.secret, scope, fresh_options)
    assert claim.call.id == call.id
    assert claim.call.initial_variables == call.initial_variables
    assert claim.call.plan == call.plan
    assert claim.call.started_at == nil
  end

  test "leaves a token unused when its call has already ended", context do
    assert {:ok, call, token} = prepare(context)

    assert {1, nil} =
             Repo.update_all(
               from(stored in StoredCall, where: stored.public_id == ^call.id),
               set: [state: :ended, ended_at: @now]
             )

    assert {:error, :call_unavailable} =
             Calls.claim_join_token(token.secret, scope(context, call), context.options)

    assert Repo.get_by!(StoredJoinToken, public_id: token.id).consumed_at == nil
    assert Repo.aggregate(StoredAdmission, :count) == 0
  end

  test "persists the first live-start occurrence idempotently", context do
    assert {:ok, call, token} = prepare(context)

    assert {:ok, claim} =
             Calls.claim_join_token(token.secret, scope(context, call), context.options)

    started_at = DateTime.add(@now, 12, :second)

    assert {:ok, running} =
             Calls.mark_call_started(claim, "rinc_persisted", started_at, context.options)

    assert running.state == :running
    assert running.started_at == started_at
    assert running.incarnation_id == "rinc_persisted"

    assert {:ok, duplicate} =
             Calls.mark_call_started(
               claim,
               "rinc_not_replacement",
               DateTime.add(started_at, 20, :second),
               context.options
             )

    assert duplicate.started_at == started_at
    assert duplicate.incarnation_id == "rinc_persisted"
  end

  test "admits another pinned participant into a running call without resetting its start",
       context do
    assert {:ok, call, caller_token} = prepare(context)

    assert {:ok, caller_claim} =
             Calls.claim_join_token(caller_token.secret, scope(context, call), context.options)

    started_at = DateTime.add(@now, 12, :second)

    assert {:ok, _running} =
             Calls.mark_call_started(
               caller_claim,
               "rinc_existing-call",
               started_at,
               context.options
             )

    support_options =
      Keyword.merge(context.options,
        token_id_generator: fn -> "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee" end,
        join_token_generator: fn -> "vxj_test-only-support-participant-token" end
      )

    assert {:ok, support_token} =
             Calls.issue_join_token(
               context.principal,
               call.id,
               context.support_route.key,
               support_options
             )

    support_scope = %{
      tenant_key: context.tenant.key,
      call_id: call.id,
      participant_key: context.support_route.key
    }

    assert {:ok, support_claim} =
             Calls.claim_join_token(support_token.secret, support_scope, support_options)

    assert support_claim.participant_ref == "support"
    assert support_claim.call.state == :running
    assert support_claim.call.started_at == started_at
    assert support_claim.call.incarnation_id == "rinc_existing-call"
    assert Repo.aggregate(StoredAdmission, :count) == 2
  end

  test "persists a terminal pre-live failure with no start time", context do
    assert {:ok, call, token} = prepare(context)

    assert {:ok, claim} =
             Calls.claim_join_token(token.secret, scope(context, call), context.options)

    assert {:ok, failed} =
             Calls.mark_call_failed(claim, :room_start_failed, context.options)

    assert failed.state == :failed
    assert failed.started_at == nil
    assert failed.ended_at == @now
    assert failed.terminal_reason == :room_start_failed

    assert %StoredCall{
             state: :failed,
             started_at: nil,
             terminal_reason: :room_start_failed
           } = Repo.get_by!(StoredCall, public_id: call.id)
  end

  test "persists exact variable history without regressing the latest pointer", context do
    {call, incarnation_id} = running_call(context)

    second = variable_snapshot(call, incarnation_id, 2, "snapshot-2")
    baseline = variable_snapshot(call, incarnation_id, 0, "snapshot-0")
    first = variable_snapshot(call, incarnation_id, 1, "snapshot-1")

    assert {:ok, ^second} = Calls.archive_variable_snapshot(second, context.options)
    assert {:ok, ^baseline} = Calls.archive_variable_snapshot(baseline, context.options)
    assert {:ok, ^first} = Calls.archive_variable_snapshot(first, context.options)
    assert {:ok, ^second} = Calls.archive_variable_snapshot(second, context.options)

    assert {:ok, history} =
             Calls.fetch_variable_snapshots(context.principal, call.id, context.options)

    assert Enum.map(history.snapshots, & &1.global_revision) == [0, 1, 2]
    assert history.latest.id == second.id
    assert history.latest.sections == second.sections
    assert Repo.aggregate(StoredVariableSnapshot, :count) == 3

    stored_call = Repo.get_by!(StoredCall, public_id: call.id)

    assert stored_call.latest_variables_snapshot_id ==
             Repo.get_by!(StoredVariableSnapshot, public_id: second.id).id
  end

  test "rejects wrong scope and conflicting variable revisions atomically", context do
    {call, incarnation_id} = running_call(context)
    accepted = variable_snapshot(call, incarnation_id, 1, "snapshot-accepted")

    assert {:ok, ^accepted} = Calls.archive_variable_snapshot(accepted, context.options)

    wrong_incarnation =
      variable_snapshot(call, "rinc_another", 2, "snapshot-wrong-incarnation")

    assert {:error, :call_incarnation_mismatch} =
             Calls.archive_variable_snapshot(wrong_incarnation, context.options)

    wrong_call =
      %{
        variable_snapshot(call, incarnation_id, 2, "snapshot-wrong-call")
        | call_id: Ecto.UUID.generate()
      }

    assert {:error, :call_not_found} =
             Calls.archive_variable_snapshot(wrong_call, context.options)

    conflicting = variable_snapshot(call, incarnation_id, 1, "snapshot-conflicting")

    assert {:error, :variable_snapshot_revision_conflict} =
             Calls.archive_variable_snapshot(conflicting, context.options)

    assert {:ok, history} =
             Calls.fetch_variable_snapshots(context.principal, call.id, context.options)

    assert Enum.map(history.snapshots, & &1.id) == [accepted.id]
    assert history.latest.id == accepted.id
    assert Repo.aggregate(StoredVariableSnapshot, :count) == 1
  end

  test "EctoStorage projects exact engine baseline and update facts", context do
    {call, incarnation_id} = running_call(context)

    baseline = %BaselineSnapshot{
      id: "vsnap-engine-baseline",
      tenant_id: call.tenant_key,
      call_id: call.id,
      room_id: call.room_id,
      incarnation_id: incarnation_id,
      global_revision: 0,
      sections: %{"order" => %{revision: 0, value: %{"id" => "ORD-0"}}},
      source_policy: %{"revision" => 0},
      occurred_at: @now
    }

    update = %UpdateSnapshot{
      id: "vsnap-engine-update",
      command_id: "command-engine",
      tenant_id: call.tenant_key,
      call_id: call.id,
      room_id: call.room_id,
      incarnation_id: incarnation_id,
      participant_id: "participant-engine",
      activation_id: "activation-engine",
      source_participant_id: "source-engine",
      correlation_id: "correlation-engine",
      tool_call_id: "tool-engine",
      section: "order",
      section_revision: 1,
      global_revision: 1,
      sections: %{"order" => %{revision: 1, value: %{"id" => "ORD-1"}}},
      source_policy: %{"revision" => 0},
      occurred_at: DateTime.add(@now, 1, :second)
    }

    assert :ok = EctoStorage.write(context.options, baseline)
    assert :ok = EctoStorage.write(context.options, update)
    assert :ok = EctoStorage.write(context.options, update)

    assert {:ok, history} =
             Calls.fetch_variable_snapshots(context.principal, call.id, context.options)

    assert Enum.map(history.snapshots, &{&1.id, &1.kind}) == [
             {baseline.id, :baseline},
             {update.id, :update}
           ]

    assert history.latest.id == update.id
    assert history.latest.command_id == update.command_id

    assert {:discard, :call_not_found} =
             EctoStorage.write(context.options, %{baseline | call_id: Ecto.UUID.generate()})
  end

  test "EctoStorage deduplicates and orders tenant-scoped private call facts", context do
    {call, incarnation_id} = running_call(context)

    later =
      engine_fact(call, incarnation_id, 2, "event-later", :agent_output_generated, %{
        "text" => "Hello back."
      })

    earlier =
      engine_fact(call, incarnation_id, 1, "event-earlier", :accepted_input, %{
        "content" => "Hello",
        "modality" => "text"
      })

    assert :ok = EctoStorage.write(context.options, later)
    assert :ok = EctoStorage.write(context.options, earlier)
    assert :ok = EctoStorage.write(context.options, earlier)

    closure =
      engine_fact(call, incarnation_id, 3, "event-closure", :archive_stream_closed, %{
        "accepted" => 2,
        "discarded" => 0,
        "incomplete" => false,
        "overflow" => 0,
        "retries" => 0,
        "source_reason" => "normal",
        "unavailable" => 0
      })

    assert :ok = EctoStorage.write(context.options, closure)

    assert {:ok, [stored_earlier, stored_later, stored_closure]} =
             Calls.fetch_call_facts(context.principal, call.id, context.options)

    assert stored_earlier.id == earlier.id
    assert stored_earlier.payload == earlier.payload
    assert stored_later.id == later.id
    assert stored_closure.id == closure.id
    assert Repo.aggregate(StoredCallFact, :count) == 3

    assert {:ok, history} =
             Calls.fetch_call_history(context.principal, call.id, context.options)

    assert history.archive_status.state == :complete
    assert history.archive_status.complete?

    conflicting = %{earlier | payload: %{"content" => "different"}}
    assert {:discard, :call_fact_conflict} = EctoStorage.write(context.options, conflicting)

    wrong_incarnation = %{later | id: "event-wrong", incarnation_id: "rinc-wrong"}

    assert {:discard, :call_incarnation_mismatch} =
             EctoStorage.write(context.options, wrong_incarnation)

    invalid_room = %{later | id: "event-invalid-room", room_id: "not-a-uuid"}
    assert {:discard, :call_fact_insert_failed} = EctoStorage.write(context.options, invalid_room)
  end

  test "pages persisted facts and variable revisions on one tenant detail", context do
    {call, incarnation_id} = running_call(context)

    started =
      engine_fact(
        call,
        incarnation_id,
        1,
        "event-inspection-started",
        :tool_call_started,
        %{"arguments" => %{}, "name" => "slow_lookup"}
      )

    started = %{started | tool_call_id: "tool-inspection"}

    completed =
      engine_fact(
        call,
        incarnation_id,
        3,
        "event-inspection-completed",
        :tool_call_completed,
        %{"name" => "slow_lookup", "result" => %{"ok" => true}}
      )

    completed = %{completed | tool_call_id: "tool-inspection"}

    snapshot = variable_snapshot(call, incarnation_id, 1, "snapshot-inspection")

    snapshot = %{
      snapshot
      | tool_call_id: "tool-inspection",
        occurred_at: DateTime.add(@now, 2, :second)
    }

    assert :ok = EctoStorage.write(context.options, started)
    assert {:ok, ^snapshot} = Calls.archive_variable_snapshot(snapshot, context.options)
    assert :ok = EctoStorage.write(context.options, completed)

    assert {:ok, first_page} =
             Calls.inspect_call(context.principal, call.id, context.options ++ [limit: 2])

    assert first_page.call.id == call.id
    assert first_page.call.latest_variable_revision == 1
    assert first_page.persisted_variable_revision == 1
    assert first_page.archive_status.state == :unconfirmed
    assert first_page.archive_status.last_sequence == 3
    assert first_page.archive_status.missing_sequences == [2]

    assert Enum.map(first_page.timeline, & &1.kind) == [
             :tool_call_completed,
             :variable_snapshot
           ]

    assert is_binary(first_page.next_cursor)

    assert {:ok, second_page} =
             Calls.inspect_call(
               context.principal,
               call.id,
               context.options ++ [limit: 2, cursor: first_page.next_cursor]
             )

    assert Enum.map(second_page.timeline, & &1.kind) == [:tool_call_started]
    assert second_page.next_cursor == nil

    other_tenant = %{context.principal | tenant_key: "ZZZZZZZZZZZZZZZZ"}
    assert {:error, :call_not_found} = Calls.inspect_call(other_tenant, call.id, context.options)
  end

  test "the bounded subscriber projects retained facts and snapshots before archive closure",
       context do
    {call, incarnation_id} = running_call(context)

    assert {:ok, handoff} =
             ArchiveSupervisor.open(
               writer: {EctoStorage, context.options},
               maximum_pending_facts: 4,
               retry_delay_ms: 5,
               drain_timeout_ms: 1_000
             )

    source = spawn(fn -> Process.sleep(:infinity) end)
    assert :ok = Handoff.source_started(handoff, source)

    baseline = %BaselineSnapshot{
      id: "vsnap-async-baseline",
      tenant_id: call.tenant_key,
      call_id: call.id,
      room_id: call.room_id,
      incarnation_id: incarnation_id,
      global_revision: 0,
      sections: %{"order" => %{revision: 0, value: %{"id" => "ORD-0"}}},
      source_policy: %{"revision" => 0},
      occurred_at: @now
    }

    update = %UpdateSnapshot{
      id: "vsnap-async-update",
      command_id: "command-async",
      tenant_id: call.tenant_key,
      call_id: call.id,
      room_id: call.room_id,
      incarnation_id: incarnation_id,
      participant_id: "participant-async",
      activation_id: "activation-async",
      source_participant_id: "source-async",
      correlation_id: "correlation-async",
      tool_call_id: "tool-async",
      section: "order",
      section_revision: 1,
      global_revision: 1,
      sections: %{"order" => %{revision: 1, value: %{"id" => "ORD-1"}}},
      source_policy: %{"revision" => 0},
      occurred_at: DateTime.add(@now, 1, :second)
    }

    accepted_input =
      engine_fact(call, incarnation_id, 1, "event-async-input", :accepted_input, %{
        "content" => "Hello asynchronously.",
        "modality" => "text"
      })

    assert :ok = Handoff.offer(handoff, baseline)
    assert :ok = Handoff.offer(handoff, update)
    assert :ok = Handoff.offer(handoff, accepted_input)

    assert eventually(fn -> Repo.aggregate(StoredVariableSnapshot, :count) == 2 end)
    assert eventually(fn -> Repo.aggregate(StoredCallFact, :count) == 1 end)
    assert %{accepted: 3, pending: 0, retries: 0} = Handoff.stats(handoff)

    subscriber_monitor = Process.monitor(handoff.subscriber)
    Process.exit(source, :kill)
    assert_receive {:DOWN, ^subscriber_monitor, :process, _subscriber, :normal}

    assert {:ok, history} =
             Calls.fetch_variable_snapshots(context.principal, call.id, context.options)

    assert Enum.map(history.snapshots, & &1.id) == [baseline.id, update.id]
    assert history.latest.id == update.id

    assert {:ok, call_history} =
             Calls.fetch_call_history(context.principal, call.id, context.options)

    assert Enum.map(call_history.facts, & &1.kind) == [
             :accepted_input,
             :archive_stream_closed
           ]

    assert call_history.archive_status.state == :complete
    assert call_history.archive_status.complete?
  end

  defp prepare(context) do
    Calls.prepare_call(
      context.principal,
      context.route.key,
      %{"order" => %{"id" => "ORD-2048"}},
      context.options
    )
  end

  defp running_call(context) do
    assert {:ok, call, token} = prepare(context)

    assert {:ok, claim} =
             Calls.claim_join_token(token.secret, scope(context, call), context.options)

    incarnation_id = "rinc_variable-history"

    assert {:ok, running} =
             Calls.mark_call_started(
               claim,
               incarnation_id,
               DateTime.add(@now, 1),
               context.options
             )

    {running, incarnation_id}
  end

  defp variable_snapshot(call, incarnation_id, global_revision, id) do
    kind = if global_revision == 0, do: :baseline, else: :update

    attributes = [
      id: id,
      kind: kind,
      tenant_key: call.tenant_key,
      call_id: call.id,
      room_id: call.room_id,
      incarnation_id: incarnation_id,
      global_revision: global_revision,
      sections: %{
        "order" => %{
          revision: global_revision,
          value: %{"id" => "ORD-#{global_revision}"}
        }
      },
      source_policy: %{"revision" => 0, "save_transcripts" => true},
      occurred_at: DateTime.add(@now, global_revision, :second)
    ]

    attributes =
      if kind == :update do
        attributes ++
          [
            command_id: "command-#{global_revision}",
            participant_id: "participant-#{global_revision}",
            activation_id: "activation-#{global_revision}",
            source_participant_id: "source-#{global_revision}",
            correlation_id: "correlation-#{global_revision}",
            tool_call_id: "tool-#{global_revision}",
            section: "order",
            section_revision: global_revision
          ]
      else
        attributes
      end

    assert {:ok, snapshot} = VariableSnapshot.new(attributes)
    snapshot
  end

  defp engine_fact(call, incarnation_id, sequence, id, kind, payload) do
    Fact.new!(
      id: id,
      kind: kind,
      sequence: sequence,
      tenant_id: call.tenant_key,
      call_id: call.id,
      room_id: call.room_id,
      incarnation_id: incarnation_id,
      participant_id: "participant-engine",
      connection_id: "connection-engine",
      command_id: "command-engine",
      correlation_id: "turn-engine",
      public_sequence: sequence,
      occurred_at: DateTime.add(@now, sequence, :second),
      source_policy: %{"revision" => 0},
      payload: payload
    )
  end

  defp scope(context, call) do
    %{
      tenant_key: context.tenant.key,
      call_id: call.id,
      participant_key: context.route.key
    }
  end

  defp sequence(values) do
    key = {__MODULE__, make_ref()}
    Process.put(key, values)

    fn ->
      [value | rest] = Process.get(key)
      Process.put(key, rest)
      value
    end
  end

  defp eventually(predicate, attempts \\ 100)

  defp eventually(predicate, attempts) when attempts > 0 do
    if predicate.() do
      true
    else
      Process.sleep(10)
      eventually(predicate, attempts - 1)
    end
  end

  defp eventually(_predicate, 0), do: false

  defp registries do
    %{
      capability_profiles: %{
        "test-model" => %{kind: :model_inference, provider: :test, options: %{model: "test"}}
      },
      host_tools: %{}
    }
  end

  defp definition_input do
    %{
      schema_version: "20260910.02",
      name: "Persistence admission",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{model_inference: "test-model"}},
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
        "support" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Help the caller.",
          first_message: %{mode: "wait_for_input"},
          variable_permissions: %{"order" => ["read"]},
          tools: %{},
          transfers: []
        }
      }
    }
  end
end
