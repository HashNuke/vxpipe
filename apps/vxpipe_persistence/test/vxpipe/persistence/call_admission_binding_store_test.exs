defmodule Vxpipe.Persistence.CallAdmissionBindingStoreTest do
  use Vxpipe.Persistence.DataCase, async: false
  import Ecto.Query
  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Calls

  alias Vxpipe.Calls.{
    Administration,
    AdmissionClaim,
    PreparedCall,
    TestTelephonyServiceRepository
  }

  alias Vxpipe.Persistence.{CallSpecStore, CallStore, CredentialStore, Repo}
  alias Vxpipe.Persistence.Schema.{Call, TelephonyLeg}

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

  for kind <- [:web, :incoming, :outgoing] do
    @kind kind
    test "#{kind} managed binding reserves cleanup once and retains it on running joins", c do
      subject = subject(c, @kind)
      assert {:ok, :admit, :new, bound} = managed_bind(subject, "managed", c)
      assert call(bound).gateway_cleanup_required
      assert call(bound).gateway_cleanup_completed_at == nil
      assert call(bound).started_at == nil
      assert {:ok, :admit, :existing, ^bound} = managed_bind(subject, "managed", c)
      assert {:ok, :admit, ^bound} = bind(subject, "managed", c)
      assert {:error, :call_incarnation_mismatch} = managed_bind(subject, "replacement", c)
      assert {:ok, running} = started(bound, "managed", c)
      assert {:ok, :admit, :existing, joined} = managed_bind(subject, "managed", c)
      assert call(joined) == call(running)
    end

    test "#{kind} legacy running admission cannot acquire a new cleanup reservation", c do
      subject = subject(c, @kind)
      assert {:ok, running} = started(subject, "legacy", c)
      assert {:error, :cleanup_reservation_unavailable} = managed_bind(subject, "legacy", c)
      assert {:ok, stored} = Calls.fetch_call(c.tenant, call(subject).id, c.options)
      assert stored == call(running)
      refute stored.gateway_cleanup_required
    end

    test "#{kind} canceled managed admission archives closure without an invented start", c do
      subject = subject(c, @kind)
      {:ok, intent} = Calls.request_call_hangup(c.actor, c.tenant, call(subject).id, c.options)
      assert {:ok, :cancel, :new, bound} = managed_bind(subject, "canceled", c)
      assert call(bound).hangup_requested_at == intent.hangup_requested_at
      assert {:ok, :cancel, :existing, ^bound} = managed_bind(subject, "canceled", c)

      close =
        archive_fact(call(bound), 1, :archive_stream_closed, %{
          "source_reason" => ["shutdown", "call_admission_cancelled"]
        })

      assert {:ok, ^close} = Vxpipe.Persistence.ArchiveStore.store_call_fact(Repo, close)
      assert {:ok, ^close} = Vxpipe.Persistence.ArchiveStore.store_call_fact(Repo, close)
      assert {:ok, stored} = Calls.fetch_call(c.tenant, call(subject).id, c.options)
      assert stored.gateway_cleanup_required
      assert stored.state == :admitting
      assert stored.started_at == nil and stored.ended_at == nil
      assert stored.gateway_cleanup_completed_at == nil
    end

    test "#{kind} managed pre-start closure commits before cancellation intent", c do
      subject = subject(c, @kind)
      {:ok, :admit, :new, bound} = managed_bind(subject, "pending-owner", c)
      close = archive_fact(call(bound), 1, :archive_stream_closed, %{})
      assert {:ok, ^close} = Vxpipe.Persistence.ArchiveStore.store_call_fact(Repo, close)
      assert {:ok, stored} = Calls.fetch_call(c.tenant, call(subject).id, c.options)
      assert stored == call(bound)
      assert stored.started_at == nil and stored.ended_at == nil
      assert stored.hangup_requested_at == nil
    end

    test "#{kind} canceled managed startup failure can archive without changing failure evidence",
         c do
      subject = subject(c, @kind)
      {:ok, :admit, :new, bound} = managed_bind(subject, "failed-owner", c)
      {:ok, _failed} = failed(bound, c)
      later_options = Keyword.put(c.options, :now, DateTime.add(@started, 3, :second))

      {:ok, intent} =
        Calls.request_call_hangup(c.actor, c.tenant, call(subject).id, later_options)

      assert {:ok, :cancel, :existing, canceled} = managed_bind(subject, "failed-owner", c)
      close = archive_fact(call(canceled), 1, :archive_stream_closed, %{})
      assert {:ok, ^close} = Vxpipe.Persistence.ArchiveStore.store_call_fact(Repo, close)
      assert {:ok, ^intent} = Calls.fetch_call(c.tenant, call(subject).id, c.options)
      assert intent.state == :failed and intent.started_at == nil
      assert intent.terminal_reason == :startup_unknown
    end

    test "#{kind} managed archive closure commits without publishing ended", c do
      subject = subject(c, @kind)
      {:ok, :admit, :new, bound} = managed_bind(subject, "managed", c)
      {:ok, running} = started(bound, "managed", c)
      close = archive_fact(call(running), 1, :archive_stream_closed, %{})
      assert {:ok, ^close} = Vxpipe.Persistence.ArchiveStore.store_call_fact(Repo, close)
      assert {:ok, stored} = Calls.fetch_call(c.tenant, call(subject).id, c.options)
      assert stored.state == :running
      assert stored.started_at == @started
      assert stored.ended_at == nil
    end

    test "#{kind} binding pins one incarnation without inventing lifecycle progress", c do
      subject = subject(c, @kind)
      original = call(subject)
      assert {:ok, :admit, bound} = bind(subject, "owned", c)
      assert bound.__struct__ == subject.__struct__
      assert call(bound) == %{original | incarnation_id: "owned"}
      assert {:ok, :admit, ^bound} = bind(subject, "owned", c)
      assert {:error, :call_incarnation_mismatch} = bind(subject, "replacement", c)
      assert {:error, reason} = started(subject, "replacement", c)
      assert reason == start_mismatch(@kind)
      assert {:ok, running} = started(subject, "owned", c)
      assert call(running).state == :running
      assert call(running).started_at == @started
      assert {:ok, :admit, rebound} = bind(subject, "owned", c)
      assert call(rebound) == call(running)
      {:ok, intent} = Calls.request_call_hangup(c.actor, c.tenant, original.id, c.options)
      assert {:ok, :cancel, canceled} = bind(subject, "owned", c)
      assert call(canceled) == intent
      assert {:error, :call_unavailable} = started(subject, "owned", c)
      assert {:ok, ^intent} = Calls.fetch_call(c.tenant, original.id, c.options)
    end

    test "#{kind} cancellation before binding retains cleanup ownership without starting", c do
      subject = subject(c, @kind)
      original = call(subject)
      {:ok, intent} = Calls.request_call_hangup(c.actor, c.tenant, original.id, c.options)
      assert {:ok, :cancel, bound} = bind(subject, "canceled-owner", c)
      assert call(bound) == %{intent | incarnation_id: "canceled-owner"}
      assert call(bound).state == :admitting
      assert call(bound).started_at == nil
      assert {:error, :call_unavailable} = started(subject, "canceled-owner", c)

      if @kind == :incoming do
        leg = Repo.get_by!(TelephonyLeg, call_id: Repo.get_by!(Call, public_id: original.id).id)
        assert leg.state == "admitting" and leg.incarnation_id == nil
      end
    end

    test "#{kind} legacy start cannot contradict historical archive ownership", c do
      subject = subject(c, @kind)
      original = call(subject)

      {:ok, fact} =
        Vxpipe.Calls.CallFact.new(
          id: "legacy-opening",
          tenant_key: original.tenant_key,
          call_id: original.id,
          room_id: original.room_id,
          incarnation_id: "historical-owner",
          occurred_at: @created,
          source_policy: %{"revision" => 0, "save_transcripts" => true},
          kind: :room_opened,
          sequence: 1,
          payload: %{}
        )

      {:ok, ^fact} = Vxpipe.Persistence.ArchiveStore.store_call_fact(Repo, fact)
      stored = Repo.get_by!(Call, public_id: original.id)

      Repo.update!(
        Ecto.Changeset.change(stored, incarnation_id: nil, incarnation_binding_verified: false)
      )

      assert {:error, reason} = started(subject, "replacement", c)
      assert reason == start_mismatch(@kind)
      assert {:ok, ^original} = Calls.fetch_call(c.tenant, original.id, c.options)
      assert {:ok, running} = started(subject, "historical-owner", c)
      assert call(running).incarnation_id == "historical-owner"
      assert call(running).started_at == @started
    end

    test "#{kind} forged pinned call identity cannot establish ownership", c do
      subject = subject(c, @kind)

      for altered <- [
            %{call(subject) | room_id: Ecto.UUID.generate()},
            %{call(subject) | plan_digest: :crypto.strong_rand_bytes(32)},
            %{call(subject) | call_spec_revision: 999},
            %{call(subject) | tenant_key: "BBBBBBBBBBBBBBBB"}
          ] do
        assert {:error, _} = bind(replace_call(subject, altered), "forged", c)
      end

      assert {:ok, stored} = Calls.fetch_call(c.tenant, call(subject).id, c.options)
      assert stored.incarnation_id == nil
    end
  end

  test "legacy starts cannot replace a running incarnation or start a canceled admission", c do
    for kind <- [:web, :incoming, :outgoing] do
      subject = subject(c, kind)
      assert {:ok, _running} = started(subject, "legacy-owner", c)
      assert {:error, reason} = started(subject, "replacement", c)
      assert reason == start_mismatch(kind)
      {:ok, _intent} = Calls.request_call_hangup(c.actor, c.tenant, call(subject).id, c.options)
      assert {:error, :call_unavailable} = started(subject, "legacy-owner", c)
    end
  end

  test "released web claims cancel while a new running participant claim can bind the same room",
       c do
    subject = subject(c, :web)
    assert {:ok, _running} = started(subject, "owner", c)
    assert :ok = Calls.release_admission(subject, c.options)
    assert {:ok, :cancel, _} = bind(subject, "owner", c)
    next = web_claim(c, call(subject))
    assert {:ok, :admit, bound} = bind(next, "owner", c)
    assert call(bound).state == :running
    assert {:error, :call_incarnation_mismatch} = bind(next, "replacement", c)
    assert {:error, _} = bind(%{next | participant_id: "forged"}, "owner", c)
    assert {:error, _} = bind(%{next | participant_key: "forged"}, "owner", c)
    assert {:error, _} = bind(%{next | token_id: Ecto.UUID.generate()}, "owner", c)
  end

  test "failed incoming and outgoing ownership binds only for cleanup and preserves failure evidence",
       c do
    for kind <- [:incoming, :outgoing] do
      subject = subject(c, kind)

      {:ok, failed} =
        case kind do
          :incoming -> Calls.mark_incoming_telephony_failed(subject, :startup_unknown, c.options)
          :outgoing -> Calls.mark_outgoing_call_failed(subject, :startup_unknown, c.options)
        end

      assert {:ok, :cancel, bound} = bind(subject, "failed-owner", c)
      assert call(bound) == %{call(failed) | incarnation_id: "failed-owner"}
    end
  end

  test "carrier identity tampering and malformed stored plans cannot persist a binding", c do
    subject = subject(c, :incoming)
    assert {:error, _} = bind(%{subject | provider_call_control_id: "forged"}, "owner", c)
    assert {:error, _} = bind(%{subject | participant_id: "forged"}, "owner", c)

    Repo.update_all(from(row in Call, where: row.public_id == ^subject.call.id),
      set: [resolved_plan: <<0>>]
    )

    assert {:error, :call_admission_unavailable} = bind(subject, "owner", c)
    assert Repo.get_by!(Call, public_id: subject.call.id).incarnation_id == nil
  end

  test "an archive-anchored pending gate can reserve cleanup, but released ownership cannot", c do
    subject = subject(c, :web)
    opened = archive_fact(%{subject.call | incarnation_id: "opened"}, 1, :room_opened, %{})
    {:ok, ^opened} = Vxpipe.Persistence.ArchiveStore.store_call_fact(Repo, opened)
    assert {:ok, :admit, :new, _bound} = managed_bind(subject, "opened", c)

    released = subject(c, :web)
    :ok = Calls.release_admission(released, c.options)
    assert {:error, :cleanup_reservation_unavailable} = managed_bind(released, "released", c)
    assert {:ok, stored} = Calls.fetch_call(c.tenant, released.call.id, c.options)
    assert stored.incarnation_id == nil
    refute stored.gateway_cleanup_required
  end

  test "managed outgoing closure retains dial metadata while terminal state waits", c do
    subject = subject(c, :outgoing)
    {:ok, :admit, :new, bound} = managed_bind(subject, "dialed", c)
    {:ok, running} = started(bound, "dialed", c)
    submitted = archive_fact(running, 1, :outgoing_dial_submitted, %{})

    close =
      archive_fact(running, 2, :archive_stream_closed, %{
        "source_reason" => ["shutdown", ["outgoing_call", "busy"]]
      })

    {:ok, ^submitted} = Vxpipe.Persistence.ArchiveStore.store_call_fact(Repo, submitted)
    assert {:ok, ^close} = Vxpipe.Persistence.ArchiveStore.store_call_fact(Repo, close)
    assert {:ok, stored} = Calls.fetch_call(c.tenant, running.id, c.options)
    assert stored.state == :running and stored.ended_at == nil
    assert stored.outgoing_outcome == :busy
    assert stored.dial_submitted_at == submitted.occurred_at
    assert stored.dial_ended_at == close.occurred_at
  end

  test "managed closure still rejects invalid time ordering", c do
    subject = subject(c, :outgoing)
    {:ok, :admit, :new, bound} = managed_bind(subject, "pending", c)
    close = archive_fact(bound, 1, :archive_stream_closed, %{})
    before_creation = %{close | occurred_at: DateTime.add(@created, -1, :second)}

    assert {:error, :outgoing_lifecycle_conflict} =
             Vxpipe.Persistence.ArchiveStore.store_call_fact(Repo, before_creation)

    {:ok, running} = started(bound, "pending", c)
    early = %{close | occurred_at: @created}

    assert {:error, :outgoing_lifecycle_conflict} =
             Vxpipe.Persistence.ArchiveStore.store_call_fact(Repo, early)

    assert {:ok, ^running} = Calls.fetch_call(c.tenant, running.id, c.options)
  end

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

  defp managed_bind(subject, incarnation, c),
    do: Calls.bind_managed_call_admission(subject, incarnation, c.options)

  defp start_mismatch(:web), do: :call_incarnation_mismatch
  defp start_mismatch(:incoming), do: :call_unavailable
  defp start_mismatch(:outgoing), do: :outgoing_start_conflict

  defp bind(subject, incarnation, c),
    do: Calls.bind_call_admission(subject, incarnation, c.options)

  defp call(%PreparedCall{} = call), do: call
  defp call(subject), do: subject.call
  defp replace_call(%PreparedCall{}, changed), do: changed
  defp replace_call(subject, changed), do: %{subject | call: changed}

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
