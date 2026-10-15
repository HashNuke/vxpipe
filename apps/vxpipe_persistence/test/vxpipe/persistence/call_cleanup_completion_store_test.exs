defmodule Vxpipe.Persistence.CallCleanupCompletionStoreTest do
  use Vxpipe.Persistence.DataCase, async: false
  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Calls

  alias Vxpipe.Calls.{
    Administration,
    AdmissionClaim,
    PreparedCall,
    TestTelephonyServiceRepository
  }

  alias Vxpipe.Persistence.{CallSpecStore, CallStore, CredentialStore, Repo}

  @created ~U[2026-10-15 16:00:00.000000Z]
  @started ~U[2026-10-15 16:00:01.000000Z]

  setup do
    options = [
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      registries: %{host_tools: %{}},
      now: @created
    ]

    {:ok, tenant, key} = Administration.bootstrap_tenant("Admission binding", [:calls], options)
    {:ok, actor} = Calls.authenticate(tenant.key, key.secret, :calls, options)

    options =
      Keyword.put(
        options,
        :telephony_service_repository,
        TestTelephonyServiceRepository.repository([tenant])
      )

    %{tenant: tenant.key, actor: actor, options: options}
  end

  @completed ~U[2026-10-15 16:00:10.000Z]

  for kind <- [:web, :incoming, :outgoing] do
    @kind kind
    test "#{kind} canceled cleanup ends once and accepts later exact-owner close", c do
      subject = subject(c, @kind)
      {:ok, :admit, :new, bound} = Calls.bind_managed_call_admission(subject, "owner", c.options)
      {:ok, _intent} = Calls.request_call_hangup(c.actor, c.tenant, call(bound).id, c.options)
      assert {:ok, ended} = complete(call(bound), @completed, c)
      assert ended.state == :ended and ended.started_at == nil
      assert ended.terminal_reason == :api_hangup
      assert DateTime.compare(ended.ended_at, @completed) == :eq
      assert ended.gateway_cleanup_completed_at == ended.ended_at
      assert {:ok, ^ended} = complete(call(bound), DateTime.add(@completed, 5, :second), c)
      close = archive_fact(ended, 1, :archive_stream_closed, %{})
      assert {:ok, ^close} = Vxpipe.Persistence.ArchiveStore.store_call_fact(Repo, close)
      assert {:ok, ^ended} = Calls.fetch_call(c.tenant, ended.id, c.options)
    end

    for ordering <- [:archive_first, :completion_first] do
      @ordering ordering
      test "#{kind} normal #{@ordering} preserves archive end time and outgoing metadata", c do
        subject = subject(c, @kind)

        {:ok, :admit, :new, bound} =
          Calls.bind_managed_call_admission(subject, "owner", c.options)

        {:ok, started} = started(bound, "owner", c)
        running = call(started)
        close = archive_fact(running, 2, :archive_stream_closed, %{})

        if @kind == :outgoing do
          submitted = archive_fact(running, 1, :outgoing_dial_submitted, %{})
          {:ok, ^submitted} = Vxpipe.Persistence.ArchiveStore.store_call_fact(Repo, submitted)
        end

        if @ordering == :archive_first do
          {:ok, ^close} = Vxpipe.Persistence.ArchiveStore.store_call_fact(Repo, close)
          assert {:ok, _ended} = complete(running, @completed, c)
        else
          assert {:ok, acknowledged} = complete(running, @completed, c)
          assert acknowledged.state == :running and acknowledged.ended_at == nil
          assert {:error, :call_cleanup_pending} = publication_source(running)
          {:ok, ^close} = Vxpipe.Persistence.ArchiveStore.store_call_fact(Repo, close)
        end

        assert {:ok, ended} = Calls.fetch_call(c.tenant, running.id, c.options)
        assert ended.state == :ended and ended.ended_at == close.occurred_at
        assert ended.terminal_reason == nil
        assert DateTime.compare(ended.gateway_cleanup_completed_at, @completed) == :eq
        assert {:ok, _source} = publication_source(ended)
        if @kind == :outgoing, do: assert(ended.dial_ended_at == close.occurred_at)
        conflicting = %{close | id: "conflicting-close", sequence: 3, occurred_at: @completed}

        assert {:error, :call_end_conflict} =
                 Vxpipe.Persistence.ArchiveStore.store_call_fact(Repo, conflicting)
      end
    end

    test "#{kind} pre-start normal closure completes without inventing started_at", c do
      subject = subject(c, @kind)
      {:ok, :admit, :new, bound} = Calls.bind_managed_call_admission(subject, "owner", c.options)
      close = archive_fact(call(bound), 1, :archive_stream_closed, %{})
      {:ok, ^close} = Vxpipe.Persistence.ArchiveStore.store_call_fact(Repo, close)
      assert {:ok, ended} = complete(call(bound), @completed, c)
      assert ended.state == :ended and ended.started_at == nil
      assert ended.ended_at == close.occurred_at
    end
  end

  test "completion retries reevaluate intent committed after cleanup and before archive", c do
    subject = subject(c, :web)
    {:ok, :admit, :new, bound} = Calls.bind_managed_call_admission(subject, "owner", c.options)
    assert {:ok, acknowledged} = complete(call(bound), @completed, c)
    assert acknowledged.state == :admitting

    {:ok, _intent} =
      Calls.request_call_hangup(
        c.actor,
        c.tenant,
        acknowledged.id,
        Keyword.put(c.options, :now, DateTime.add(@created, 13, :second))
      )

    assert {:ok, ended} = complete(acknowledged, DateTime.add(@completed, 5, :second), c)
    assert ended.terminal_reason == :api_hangup
    assert ended.gateway_cleanup_completed_at == acknowledged.gateway_cleanup_completed_at
    assert ended.ended_at == acknowledged.gateway_cleanup_completed_at
  end

  for started? <- [false, true] do
    @started? started?
    test "archive between intent and retry preserves acknowledgement time when started=#{started?}",
         c do
      subject = subject(c, :web)
      {:ok, :admit, :new, bound} = Calls.bind_managed_call_admission(subject, "owner", c.options)

      active =
        if @started? do
          {:ok, running} = started(bound, "owner", c)
          call(running)
        else
          call(bound)
        end

      {:ok, acknowledged} = complete(active, @completed, c)
      {:ok, _intent} = Calls.request_call_hangup(c.actor, c.tenant, active.id, c.options)
      close = archive_fact(active, 1, :archive_stream_closed, %{})
      {:ok, ^close} = Vxpipe.Persistence.ArchiveStore.store_call_fact(Repo, close)
      assert {:ok, ended} = complete(active, DateTime.add(@completed, 5, :second), c)
      assert ended.terminal_reason == :api_hangup
      assert ended.ended_at == acknowledged.gateway_cleanup_completed_at
      assert ended.started_at == active.started_at
    end
  end

  test "pending failed managed calls cannot publish and completion retains failure without intent",
       c do
    subject = subject(c, :web)
    {:ok, :admit, :new, bound} = Calls.bind_managed_call_admission(subject, "owner", c.options)
    {:ok, failed} = failed(bound, c)
    assert {:error, :call_cleanup_pending} = publication_source(failed)
    assert {:ok, completed} = complete(failed, @completed, c)
    assert completed.state == :failed and completed.terminal_reason == failed.terminal_reason
    assert completed.ended_at == failed.ended_at
    assert {:ok, _source} = publication_source(completed)
  end

  test "normal conflicting archive closure is rejected while cleanup remains pending", c do
    subject = subject(c, :web)
    {:ok, :admit, :new, bound} = Calls.bind_managed_call_admission(subject, "owner", c.options)
    {:ok, running} = started(bound, "owner", c)
    close = archive_fact(running, 1, :archive_stream_closed, %{})
    {:ok, ^close} = Vxpipe.Persistence.ArchiveStore.store_call_fact(Repo, close)

    conflicting = %{
      close
      | id: "conflicting-pending-close",
        sequence: 2,
        occurred_at: DateTime.add(close.occurred_at, 1, :second)
    }

    assert {:error, :call_end_conflict} =
             Vxpipe.Persistence.ArchiveStore.store_call_fact(Repo, conflicting)

    assert {:ok, [^close]} =
             Vxpipe.Persistence.ArchiveStore.fetch_call_facts(Repo, c.tenant, running.id)

    assert {:ok, ended} = complete(running, @completed, c)
    assert ended.ended_at == close.occurred_at
  end

  test "failed acknowledged cleanup accepts close after cancellation arrives", c do
    subject = subject(c, :web)
    {:ok, :admit, :new, bound} = Calls.bind_managed_call_admission(subject, "owner", c.options)
    {:ok, failed} = failed(bound, c)
    {:ok, acknowledged} = complete(failed, @completed, c)
    {:ok, _intent} = Calls.request_call_hangup(c.actor, c.tenant, failed.id, c.options)
    close = archive_fact(failed, 1, :archive_stream_closed, %{})
    assert {:ok, ^close} = Vxpipe.Persistence.ArchiveStore.store_call_fact(Repo, close)
    assert {:ok, ended} = Calls.fetch_call(c.tenant, failed.id, c.options)
    assert ended.terminal_reason == :api_hangup
    assert ended.ended_at == acknowledged.gateway_cleanup_completed_at
  end

  test "completion rejects foreign bindings, legacy calls and invalid ordering without mutation",
       c do
    subject = subject(c, :web)
    assert {:error, :cleanup_reservation_unavailable} = complete(call(subject), @completed, c)
    {:ok, :admit, :new, bound} = Calls.bind_managed_call_admission(subject, "owner", c.options)
    current = call(bound)

    for {field, replacement, error} <- [
          {:tenant_key, "foreign", :not_found},
          {:call_id, Ecto.UUID.generate(), :not_found},
          {:room_id, "foreign", :call_room_mismatch},
          {:incarnation_id, "foreign", :call_incarnation_mismatch}
        ] do
      assert {:error, ^error} =
               Calls.complete_call_cleanup(
                 Map.put(cleanup_binding(current), field, replacement),
                 @completed,
                 c.options
               )
    end

    assert {:error, :invalid_call_cleanup} =
             complete(current, DateTime.add(@created, -1, :second), c)

    assert {:ok, ^current} = Calls.fetch_call(c.tenant, current.id, c.options)
  end

  defp complete(call, time, c),
    do: Calls.complete_call_cleanup(cleanup_binding(call), time, c.options)

  defp cleanup_binding(call),
    do: %{
      tenant_key: call.tenant_key,
      call_id: call.id,
      room_id: call.room_id,
      incarnation_id: call.incarnation_id || "owner"
    }

  defp publication_source(call),
    do: Vxpipe.Persistence.CallDetailsSourceStore.read(Repo, call.tenant_key, call.id)

  defp failed(%AdmissionClaim{} = subject, c),
    do: Calls.mark_call_failed(subject, :startup_unknown, c.options)

  defp failed(%PreparedCall{} = subject, c),
    do: Calls.mark_outgoing_call_failed(subject, :startup_unknown, c.options)

  defp failed(subject, c),
    do: Calls.mark_incoming_telephony_failed(subject, :startup_unknown, c.options)

  defp archive_fact(call, sequence, kind, payload) do
    {:ok, fact} =
      Vxpipe.Calls.CallFact.new(
        id: "managed-fact-#{sequence}",
        tenant_key: call.tenant_key,
        call_id: call.id,
        room_id: call.room_id,
        incarnation_id: call.incarnation_id,
        occurred_at: DateTime.add(@started, sequence, :second),
        sequence: sequence,
        kind: kind,
        payload: payload,
        source_policy: %{"revision" => 0}
      )

    fact
  end

  defp call(%PreparedCall{} = call), do: call
  defp call(subject), do: subject.call

  defp started(%AdmissionClaim{} = subject, incarnation, c),
    do: Calls.mark_call_started(subject, incarnation, @started, c.options)

  defp started(%PreparedCall{} = subject, incarnation, c),
    do: Calls.mark_outgoing_call_started(subject, incarnation, @started, c.options)

  defp started(subject, incarnation, c),
    do: Calls.mark_incoming_telephony_started(subject, incarnation, @started, c.options)

  defp subject(c, kind) do
    {:ok, draft} = Calls.save_call_spec(c.tenant, source(kind), c.options)
    {:ok, published} = Calls.publish_call_spec(c.tenant, draft.call_spec_id, 1, c.options)

    if kind == :incoming do
      unique = Integer.to_string(System.unique_integer([:positive]))

      event = %Event{
        kind: :incoming,
        provider: :telnyx,
        provider_event_id: "event-#{unique}",
        provider_connection_id: "connection-1",
        provider_call_control_id: "control-#{unique}",
        provider_call_leg_id: "leg-#{unique}",
        provider_call_session_id: nil,
        occurred_at: @created,
        from: "+15550001001",
        to: "+15550001000"
      }

      {:ok, claim} =
        Calls.claim_incoming_telephony({:tenant, c.tenant}, "primary-phone", event, c.options)

      claim
    else
      {:ok, call} =
        Calls.claim_call(c.actor, c.tenant, published.call_spec_id, %{}, nil, nil, c.options)

      if kind == :web, do: web_claim(c, call), else: call
    end
  end

  defp web_claim(c, call) do
    {:ok, token} = Calls.issue_call_join_token(c.actor, c.tenant, call.id, nil, c.options)
    scope = %{tenant_key: c.tenant, call_id: call.id, participant_key: token.participant_key}
    {:ok, claim} = Calls.claim_join_token(token.secret, scope, c.options)
    claim
  end

  defp source(kind) do
    connection =
      case kind do
        :web ->
          %{service: "web", mode: "receive", admission: "start_call"}

        :incoming ->
          %{
            service: "primary-phone",
            mode: "receive",
            admission: "start_call",
            number: "+15550001000"
          }

        :outgoing ->
          %{service: "primary-phone", mode: "dial", number: "+15550001000"}
      end

    base = %{
      schema_version: "20261004.01",
      incoming_call: %{caller: "caller", handled_by: "assistant"},
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
      participants: %{
        "caller" => %{type: "human", connection: connection},
        "assistant" => %{type: "agent", prompt: "Help."}
      }
    }

    if kind == :outgoing,
      do:
        base
        |> Map.delete(:incoming_call)
        |> Map.put(:outgoing_call, %{
          callee: "caller",
          handled_by: "assistant",
          ring_timeout_ms: 5_000
        }),
      else: base
  end
end
