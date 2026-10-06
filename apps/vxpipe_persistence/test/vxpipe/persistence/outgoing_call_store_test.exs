defmodule Vxpipe.Persistence.OutgoingCallStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, PreparedCallFactory, TestTelephonyServiceRepository}

  alias Vxpipe.Persistence.{
    ArchiveStore,
    CallSpecStore,
    CallStore,
    CredentialStore,
    EctoStorage,
    InspectionStore,
    Repo
  }

  alias Vxpipe.Persistence.Schema.{Call, JoinToken}

  setup do
    options = [
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      archive_repository: {ArchiveStore, Repo},
      inspection_repository: {InspectionStore, Repo},
      registries: %{host_tools: %{}}
    ]

    assert {:ok, tenant, issued} =
             Administration.bootstrap_tenant("Outgoing DB", [:calls], options)

    assert {:ok, principal} = Calls.authenticate(tenant.key, issued.secret, :calls, options)

    options =
      Keyword.put(
        options,
        :telephony_service_repository,
        TestTelephonyServiceRepository.repository([tenant])
      )

    source = %{
      schema_version: "20261004.01",
      name: "Outgoing DB",
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

    assert {:ok, draft} = Calls.save_call_spec(tenant.key, source, options)
    assert {:ok, published} = Calls.publish_call_spec(tenant.key, draft.call_spec_id, 1, options)
    %{options: options, principal: principal, published: published, source: source}
  end

  for {kind, payload} <- [
    outgoing_dial_ended: %{"outcome" => "machine"},
    archive_stream_closed: %{"source_reason" => ["shutdown", ["outgoing_call", "machine"]]}
  ] do
    test "#{kind} preserves physical answer time and classifies the machine", c do
      assert {:ok, call} = Calls.claim_outgoing_call(c.principal, c.published.call_spec_id, %{}, nil, c.options)
      started = DateTime.utc_now()
      assert {:ok, call} = Calls.mark_outgoing_call_started(call, "rinc-machine", started, c.options)
      submitted = lifecycle_fact(call, 1, :outgoing_dial_submitted, %{}, DateTime.add(started, 1, :second))
      answered = lifecycle_fact(call, 2, :outgoing_call_answered, %{"outcome" => "answered"}, DateTime.add(started, 2, :second))
      ended = lifecycle_fact(call, 3, unquote(kind), unquote(Macro.escape(payload)), DateTime.add(started, 3, :second))
      for fact <- [submitted, answered, ended, ended], do: assert(:ok = EctoStorage.write(c.options, fact))
      assert {:ok, stored} = Calls.fetch_call(call.tenant_key, call.id, c.options)
      assert stored.outgoing_outcome == :machine
      assert stored.answered_at == answered.occurred_at
      assert stored.dial_ended_at == ended.occurred_at
    end
  end

  test "projects outgoing lifecycle once through archived facts and bounded inspection", c do
    assert {:ok, call} =
             Calls.claim_outgoing_call(c.principal, c.published.call_spec_id, %{}, nil, c.options)

    started = DateTime.utc_now()

    assert {:ok, call} =
             Calls.mark_outgoing_call_started(call, "rinc-outgoing-facts", started, c.options)

    submitted =
      lifecycle_fact(call, 1, :outgoing_dial_submitted, %{}, DateTime.add(started, 1, :second))

    answered =
      lifecycle_fact(
        call,
        2,
        :outgoing_call_answered,
        %{"outcome" => "answered"},
        DateTime.add(started, 2, :second)
      )

    ended =
      lifecycle_fact(
        call,
        3,
        :outgoing_dial_ended,
        %{"outcome" => "answered"},
        DateTime.add(started, 3, :second)
      )

    for fact <- [submitted, answered, answered, ended, ended],
        do: assert(:ok = EctoStorage.write(c.options, fact))

    assert {:ok, stored} = Calls.fetch_call(call.tenant_key, call.id, c.options)
    assert stored.outgoing_outcome == :answered
    assert stored.dial_submitted_at == submitted.occurred_at
    assert stored.answered_at == answered.occurred_at
    assert stored.dial_ended_at == ended.occurred_at
    assert stored.state == :running

    closure =
      lifecycle_fact(
        call,
        5,
        :archive_stream_closed,
        %{"source_reason" => ["shutdown", ["outgoing_call", "answered"]]},
        DateTime.add(started, 5, :second)
      )

    assert :ok = EctoStorage.write(c.options, closure)
    assert :ok = EctoStorage.write(c.options, closure)
    assert {:ok, stored} = Calls.fetch_call(call.tenant_key, call.id, c.options)
    assert stored.state == :ended
    assert stored.outgoing_outcome == :answered
    assert {:ok, summary} = InspectionStore.fetch_call(Repo, call.tenant_key, call.id)
    assert summary.outgoing_outcome == :answered
    assert summary.dial_submitted_at == submitted.occurred_at
    assert summary.answered_at == answered.occurred_at
    assert summary.dial_ended_at == ended.occurred_at

    lifecycle =
      Vxpipe.Persistence.CallDetailsCallProjection.call(stored) |> Map.fetch!("lifecycle")

    assert lifecycle["outgoing_outcome"] == "answered"
    assert lifecycle["dial_submitted_at"] == DateTime.to_iso8601(submitted.occurred_at)
    assert lifecycle["answered_at"] == DateTime.to_iso8601(answered.occurred_at)
    assert lifecycle["dial_ended_at"] == DateTime.to_iso8601(ended.occurred_at)

    late =
      lifecycle_fact(
        call,
        4,
        :outgoing_dial_ended,
        %{"outcome" => "busy"},
        DateTime.add(started, 4, :second)
      )

    assert :ok = EctoStorage.write(c.options, late)
    assert {:ok, ^stored} = Calls.fetch_call(call.tenant_key, call.id, c.options)
  end

  test "terminal evidence survives HTTP failure projection and cannot be replaced by an answer",
       c do
    assert {:ok, call} =
             Calls.claim_outgoing_call(c.principal, c.published.call_spec_id, %{}, nil, c.options)

    started = DateTime.utc_now()

    assert {:ok, call} =
             Calls.mark_outgoing_call_started(call, "rinc-outgoing-failure", started, c.options)

    assert {:ok, _} = Calls.mark_outgoing_call_failed(call, :room_start_failed, c.options)
    submitted = lifecycle_fact(call, 1, :outgoing_dial_submitted, %{}, started)

    ended =
      lifecycle_fact(
        call,
        2,
        :outgoing_dial_ended,
        %{"outcome" => "failed"},
        DateTime.add(started, 1, :second)
      )

    assert :ok = EctoStorage.write(c.options, submitted)
    assert :ok = EctoStorage.write(c.options, ended)

    late =
      lifecycle_fact(
        call,
        3,
        :outgoing_call_answered,
        %{"outcome" => "answered"},
        DateTime.add(started, 2, :second)
      )

    assert :ok = EctoStorage.write(c.options, late)
    assert {:ok, stored} = Calls.fetch_call(call.tenant_key, call.id, c.options)
    assert stored.state == :failed
    assert stored.outgoing_outcome == :failed
    assert stored.answered_at == nil
    assert stored.dial_ended_at == ended.occurred_at

    closure =
      lifecycle_fact(
        call,
        4,
        :archive_stream_closed,
        %{"source_reason" => ["shutdown", ["outgoing_call", "failed"]]},
        DateTime.add(started, 3, :second)
      )

    assert :ok = EctoStorage.write(c.options, closure)
    assert :ok = EctoStorage.write(c.options, closure)
    assert {:ok, ^stored} = Calls.fetch_call(call.tenant_key, call.id, c.options)
  end

  test "rejects outgoing facts with foreign incarnation, private payload or inverted time", c do
    assert {:ok, call} =
             Calls.claim_outgoing_call(c.principal, c.published.call_spec_id, %{}, nil, c.options)

    started = DateTime.utc_now()

    assert {:ok, call} =
             Calls.mark_outgoing_call_started(call, "rinc-outgoing-reject", started, c.options)

    fact = lifecycle_fact(call, 1, :outgoing_dial_submitted, %{}, started)

    assert {:discard, :call_incarnation_mismatch} =
             EctoStorage.write(c.options, %{fact | incarnation_id: "foreign"})

    assert {:discard, :invalid_call_fact} =
             EctoStorage.write(c.options, %{fact | payload: %{"phone" => "+15550001000"}})

    assert {:discard, :outgoing_lifecycle_conflict} =
             EctoStorage.write(c.options, %{
               fact
               | occurred_at: DateTime.add(started, -1, :second)
             })
  end

  test "closure completes an answered dial after unexpected room termination", c do
    assert {:ok, call} =
             Calls.claim_outgoing_call(c.principal, c.published.call_spec_id, %{}, nil, c.options)

    started = DateTime.utc_now()

    assert {:ok, call} =
             Calls.mark_outgoing_call_started(call, "rinc-closure", started, c.options)

    assert :ok =
             EctoStorage.write(
               c.options,
               lifecycle_fact(call, 1, :outgoing_dial_submitted, %{}, started)
             )

    answered = DateTime.add(started, 1, :second)

    assert :ok =
             EctoStorage.write(
               c.options,
               lifecycle_fact(
                 call,
                 2,
                 :outgoing_call_answered,
                 %{"outcome" => "answered"},
                 answered
               )
             )

    ended = DateTime.add(started, 2, :second)

    assert :ok =
             EctoStorage.write(
               c.options,
               lifecycle_fact(
                 call,
                 3,
                 :archive_stream_closed,
                 %{"source_reason" => "killed"},
                 ended
               )
             )

    assert {:ok, stored} = Calls.fetch_call(call.tenant_key, call.id, c.options)
    assert stored.state == :ended
    assert stored.outgoing_outcome == :answered
    assert stored.answered_at == answered
    assert stored.dial_ended_at == ended
  end

  test "closure without an answer leaves an interrupted dial unknown", c do
    assert {:ok, call} =
             Calls.claim_outgoing_call(c.principal, c.published.call_spec_id, %{}, nil, c.options)

    started = DateTime.utc_now()

    assert {:ok, call} =
             Calls.mark_outgoing_call_started(call, "rinc-interrupted", started, c.options)

    assert :ok =
             EctoStorage.write(
               c.options,
               lifecycle_fact(call, 1, :outgoing_dial_submitted, %{}, started)
             )

    ended = DateTime.add(started, 1, :second)

    assert :ok =
             EctoStorage.write(
               c.options,
               lifecycle_fact(
                 call,
                 2,
                 :archive_stream_closed,
                 %{"source_reason" => "killed"},
                 ended
               )
             )

    assert {:ok, stored} = Calls.fetch_call(call.tenant_key, call.id, c.options)
    assert stored.outgoing_outcome == :unknown
    assert stored.dial_ended_at == ended
    assert stored.answered_at == nil
  end

  test "failed preparation records its bounded outcome without fabricating dial times", c do
    assert {:ok, call} =
             Calls.claim_outgoing_call(c.principal, c.published.call_spec_id, %{}, nil, c.options)

    assert {:ok, failed} = Calls.mark_outgoing_call_failed(call, :room_start_failed, c.options)
    assert failed.outgoing_outcome == :failed
    assert failed.dial_submitted_at == nil
    assert failed.answered_at == nil
    assert failed.dial_ended_at == nil
    assert {:ok, ^failed} = Calls.mark_outgoing_call_failed(call, :startup_unknown, c.options)
  end

  test "preparation closure records failure even when it reaches storage before HTTP", c do
    assert {:ok, call} =
             Calls.claim_outgoing_call(c.principal, c.published.call_spec_id, %{}, nil, c.options)

    started = DateTime.utc_now()

    assert {:ok, call} =
             Calls.mark_outgoing_call_started(
               call,
               "rinc-preparation-closure",
               started,
               c.options
             )

    assert :ok =
             EctoStorage.write(
               c.options,
               lifecycle_fact(
                 call,
                 1,
                 :archive_stream_closed,
                 %{"source_reason" => "startup_unavailable"},
                 DateTime.add(started, 1, :second)
               )
             )

    assert {:ok, stored} = Calls.fetch_call(call.tenant_key, call.id, c.options)
    assert stored.outgoing_outcome == :failed
    assert stored.dial_submitted_at == nil
    assert stored.dial_ended_at == nil
    assert {:ok, ^stored} = Calls.mark_outgoing_call_failed(call, :room_start_failed, c.options)
  end

  test "SQL rejects an answer timestamp without its answered outcome", c do
    assert {:ok, call} =
             Calls.claim_outgoing_call(c.principal, c.published.call_spec_id, %{}, nil, c.options)

    started = DateTime.utc_now()
    assert {:ok, _call} = Calls.mark_outgoing_call_started(call, "rinc-sql", started, c.options)
    stored = Repo.get_by!(Call, public_id: call.id)

    changeset =
      stored
      |> Ecto.Changeset.change(dial_submitted_at: started, answered_at: started)
      |> Ecto.Changeset.check_constraint(:answered_at, name: :calls_outgoing_times)

    assert {:error, invalid} = Repo.update(changeset)
    assert Keyword.has_key?(invalid.errors, :answered_at)
  end

  for outcome <- [:no_answer, :busy, :rejected, :failed, :machine, :unknown] do
    @outcome outcome
    test "persists bounded #{@outcome} and ignores later answer evidence", c do
      assert {:ok, call} =
               Calls.claim_outgoing_call(
                 c.principal,
                 c.published.call_spec_id,
                 %{},
                 nil,
                 c.options
               )

      started = DateTime.utc_now()

      assert {:ok, call} =
               Calls.mark_outgoing_call_started(call, "rinc-outcome", started, c.options)

      assert :ok =
               EctoStorage.write(
                 c.options,
                 lifecycle_fact(call, 1, :outgoing_dial_submitted, %{}, started)
               )

      ended = DateTime.add(started, 1, :second)

      assert :ok =
               EctoStorage.write(
                 c.options,
                 lifecycle_fact(
                   call,
                   2,
                   :outgoing_dial_ended,
                   %{"outcome" => Atom.to_string(@outcome)},
                   ended
                 )
               )

      assert :ok =
               EctoStorage.write(
                 c.options,
                 lifecycle_fact(
                   call,
                   3,
                   :outgoing_call_answered,
                   %{"outcome" => "answered"},
                   DateTime.add(ended, 1, :second)
                 )
               )

      assert {:ok, stored} = Calls.fetch_call(call.tenant_key, call.id, c.options)
      assert stored.outgoing_outcome == @outcome
      assert stored.answered_at == nil
      assert stored.dial_ended_at == ended
    end
  end

  defp lifecycle_fact(call, sequence, kind, payload, occurred) do
    Vxpipe.CallEngine.Archive.Fact.new!(
      id: "outgoing-fact-#{sequence}",
      kind: kind,
      sequence: sequence,
      tenant_id: call.tenant_key,
      call_id: call.id,
      room_id: call.room_id,
      incarnation_id: call.incarnation_id,
      occurred_at: occurred,
      source_policy: %{"revision" => 0},
      payload: payload
    )
  end

  test "pins durable start to one incarnation and never revives a failed call", c do
    assert {:ok, call} =
             Calls.claim_outgoing_call(
               c.principal,
               c.published.call_spec_id,
               %{},
               "start-once",
               c.options
             )

    started = DateTime.utc_now()

    assert {:ok, running} =
             Calls.mark_outgoing_call_started(call, "rinc-db-outgoing", started, c.options)

    assert running.state == :running
    assert running.started_at == started

    assert {:ok, ^running} =
             Calls.mark_outgoing_call_started(
               call,
               "rinc-db-outgoing",
               DateTime.add(started, 1, :second),
               c.options
             )

    assert {:error, :outgoing_start_conflict} =
             Calls.mark_outgoing_call_started(call, "foreign-incarnation", started, c.options)

    assert {:error, :outgoing_call_mismatch} =
             Calls.mark_outgoing_call_started(
               %{call | plan_digest: :crypto.hash(:sha256, "other-plan")},
               "rinc-db-outgoing",
               started,
               c.options
             )

    assert {:ok, failed} = Calls.mark_outgoing_call_failed(call, :room_start_failed, c.options)
    assert failed.state == :failed
    assert failed.started_at == started

    assert {:error, :outgoing_start_conflict} =
             Calls.mark_outgoing_call_started(call, "rinc-db-outgoing", started, c.options)

    assert {:ok, ^failed} = Calls.mark_outgoing_call_failed(call, :startup_unknown, c.options)
  end

  test "stores one admitted call without join tokens and replays the original", c do
    assert {:ok, first} =
             Calls.claim_outgoing_call(
               c.principal,
               c.published.call_spec_id,
               %{},
               "db-key",
               c.options
             )

    assert first.state == :admitting
    assert byte_size(first.idempotency_digest) == 32

    assert {:duplicate, ^first} =
             Calls.claim_outgoing_call(
               c.principal,
               c.published.call_spec_id,
               %{},
               "db-key",
               c.options
             )

    assert Repo.aggregate(Call, :count) == 1
    assert Repo.aggregate(JoinToken, :count) == 0
  end

  test "atomic unique-key recovery compares digests after rollback", c do
    assert {:ok, prepared} = PreparedCallFactory.build(c.published, %{}, :telephony, c.options)

    first = %{
      prepared
      | state: :admitting,
        idempotency_key: "atomic-key",
        idempotency_digest: :crypto.hash(:sha256, "one")
    }

    authorize = fn ->
      assert Repo.in_transaction?()
      {:ok, :authorized}
    end

    assert {:ok, _first} = CallStore.claim_outgoing_call(Repo, first, authorize)
    raced = %{first | id: Vxpipe.Calls.PublicId.uuid(), room_id: Vxpipe.Calls.PublicId.uuid()}
    assert {:duplicate, loaded} = CallStore.claim_outgoing_call(Repo, raced, authorize)
    assert loaded.id == first.id

    assert {:error, :idempotency_conflict} =
             CallStore.claim_outgoing_call(
               Repo,
               %{raced | idempotency_digest: :crypto.hash(:sha256, "changed")},
               authorize
             )

    assert Repo.aggregate(Call, :count) == 1
  end

  test "a failed final authorization rolls back before insertion", c do
    assert {:ok, prepared} = PreparedCallFactory.build(c.published, %{}, :telephony, c.options)

    assert {:error, :credential_unavailable} =
             CallStore.claim_outgoing_call(Repo, %{prepared | state: :admitting}, fn ->
               assert Repo.in_transaction?()
               {:error, :credential_unavailable}
             end)

    assert Repo.aggregate(Call, :count) == 0
  end

  test "the selected published revision survives later drafts and republication", c do
    options = Keyword.put(c.options, :call_spec_id, c.published.call_spec_id)
    assert {:ok, second} = Calls.save_call_spec(c.principal.tenant_key, c.source, options)

    assert {:ok, selected} =
             CallSpecStore.fetch_published_revision(
               Repo,
               c.principal.tenant_key,
               second.call_spec_id
             )

    assert selected.revision == 1

    assert {:ok, _} =
             Calls.publish_call_spec(c.principal.tenant_key, second.call_spec_id, 2, c.options)

    assert {:ok, _} =
             Calls.publish_call_spec(c.principal.tenant_key, second.call_spec_id, 1, c.options)

    assert {:ok, selected} =
             CallSpecStore.fetch_published_revision(
               Repo,
               c.principal.tenant_key,
               second.call_spec_id
             )

    assert selected.revision == 1
    assert {:ok, draft} = Calls.save_call_spec(c.principal.tenant_key, c.source, c.options)

    assert {:error, :call_spec_not_published} =
             CallSpecStore.fetch_published_revision(
               Repo,
               c.principal.tenant_key,
               draft.call_spec_id
             )

    assert {:error, :not_found} =
             CallSpecStore.fetch_published_revision(Repo, "foreign", c.published.call_spec_id)
  end
end
