defmodule Vxpipe.Persistence.CallHangupStoreTest do
  use Vxpipe.Persistence.DataCase, async: false
  import Ecto.Query
  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, TestTelephonyServiceRepository}
  alias Vxpipe.Persistence.{CallSpecStore, CallStore, CredentialStore, Repo}
  alias Vxpipe.Persistence.Schema.{Admission, Call, JoinToken}

  @created ~U[2026-10-15 16:00:00.000000Z]
  @requested ~U[2026-10-15 16:00:01.000000Z]

  setup do
    options = [
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      registries: %{host_tools: %{}},
      now: @created
    ]

    {:ok, tenant, key} = Administration.bootstrap_tenant("Hangup intent", [:calls], options)
    {:ok, actor} = Calls.authenticate(tenant.key, key.secret, :calls, options)
    {:ok, draft} = Calls.save_call_spec(tenant.key, source(), options)
    {:ok, published} = Calls.publish_call_spec(tenant.key, draft.call_spec_id, 1, options)

    %{
      tenant: tenant.key,
      tenant_record: tenant,
      actor: actor,
      options: options,
      spec: published.call_spec_id
    }
  end

  test "prepared cancellation ends atomically and leaves outstanding tokens unusable", c do
    call = prepare(c)
    {:ok, token} = Calls.issue_call_join_token(c.actor, c.tenant, call.id, nil, c.options)
    assert {:ok, ended} = hangup(c, call.id)
    assert ended.state == :ended
    assert ended.ended_at == @requested
    assert ended.started_at == nil and ended.incarnation_id == nil
    assert ended.terminal_reason == :api_hangup
    assert ended.hangup_requested_at == @requested
    assert {:ok, ^ended} = Calls.fetch_call(c.tenant, call.id, c.options)
    assert {:ok, ^ended} = hangup(c, call.id, DateTime.add(@requested, 20))
    assert Repo.aggregate(Admission, :count) == 0

    assert {:error, :call_unavailable} =
             Calls.issue_call_join_token(c.actor, c.tenant, call.id, nil, c.options)

    assert {:error, :call_unavailable} =
             Calls.claim_join_token(token.secret, scope(c, token), c.options)

    assert Repo.get_by!(JoinToken, public_id: token.id).consumed_at == nil
  end

  test "claimed, running and failed calls retain truthful lifecycle and first cancellation intent",
       c do
    for state <- [:admitting, :running, :failed] do
      call = prepare(c)
      {:ok, first} = Calls.issue_call_join_token(c.actor, c.tenant, call.id, nil, c.options)
      {:ok, spare} = Calls.issue_call_join_token(c.actor, c.tenant, call.id, nil, c.options)
      {:ok, claim} = Calls.claim_join_token(first.secret, scope(c, first), c.options)

      before =
        case state do
          :admitting ->
            claim.call

          :running ->
            {:ok, started} = Calls.mark_call_started(claim, "incarnation", @created, c.options)
            started

          :failed ->
            {:ok, failed} = Calls.mark_call_failed(claim, :startup_unknown, c.options)
            failed
        end

      assert {:ok, intent} = hangup(c, call.id)
      assert intent.hangup_requested_at == @requested

      assert Map.take(intent, [
               :state,
               :started_at,
               :ended_at,
               :terminal_reason,
               :incarnation_id,
               :outgoing_outcome
             ]) ==
               Map.take(before, [
                 :state,
                 :started_at,
                 :ended_at,
                 :terminal_reason,
                 :incarnation_id,
                 :outgoing_outcome
               ])

      assert intent.state == state
      assert {:ok, ^intent} = hangup(c, call.id, DateTime.add(@requested, 10))

      assert {:error, :call_unavailable} =
               Calls.issue_call_join_token(c.actor, c.tenant, call.id, nil, c.options)

      assert {:error, :call_unavailable} =
               Calls.claim_join_token(spare.secret, scope(c, spare), c.options)

      assert Repo.get_by!(JoinToken, public_id: spare.id).consumed_at == nil
    end
  end

  test "prepared-looking rows with admission history do not acquire false terminal evidence", c do
    call = prepare(c)
    {:ok, token} = Calls.issue_call_join_token(c.actor, c.tenant, call.id, nil, c.options)
    {:ok, _claim} = Calls.claim_join_token(token.secret, scope(c, token), c.options)
    Repo.update_all(from(row in Call, where: row.public_id == ^call.id), set: [state: :prepared])
    assert {:ok, intent} = hangup(c, call.id)
    assert intent.state == :prepared
    assert intent.ended_at == nil
    assert intent.hangup_requested_at == @requested
  end

  test "failed outgoing startup retains its unknown carrier outcome and lifecycle evidence", c do
    options =
      Keyword.put(
        c.options,
        :telephony_service_repository,
        TestTelephonyServiceRepository.repository([c.tenant_record])
      )

    outgoing =
      source()
      |> Map.delete(:incoming_call)
      |> Map.put(:outgoing_call, %{
        callee: "caller",
        handled_by: "assistant",
        ring_timeout_ms: 5_000
      })
      |> put_in(
        [:participants, "caller", :connection],
        %{service: "primary-phone", mode: "dial", number: "+15550001000"}
      )

    {:ok, draft} = Calls.save_call_spec(c.tenant, outgoing, options)
    {:ok, published} = Calls.publish_call_spec(c.tenant, draft.call_spec_id, 1, options)

    {:ok, call} =
      Calls.claim_call(c.actor, c.tenant, published.call_spec_id, %{}, nil, nil, options)

    {:ok, failed} = Calls.mark_outgoing_call_failed(call, :startup_unknown, options)
    assert failed.outgoing_outcome == :unknown
    assert {:ok, intent} = hangup(c, call.id)
    assert intent.state == :failed
    assert intent.outgoing_outcome == :unknown
    assert intent.terminal_reason == :startup_unknown
    assert intent.ended_at == failed.ended_at
    assert intent.hangup_requested_at == @requested
  end

  test "a stored plan decode failure rolls back cancellation intent and terminal changes", c do
    call = prepare(c)

    Repo.update_all(from(row in Call, where: row.public_id == ^call.id),
      set: [resolved_plan: <<0>>]
    )

    assert {:error, :call_hangup_unavailable} = hangup(c, call.id)
    stored = Repo.get_by!(Call, public_id: call.id)
    assert stored.state == :prepared
    assert stored.hangup_requested_at == nil
    assert stored.ended_at == nil
    assert stored.terminal_reason == nil
  end

  test "already-ended calls remain unchanged and foreign or absent calls cannot be selected", c do
    call = prepare(c)

    Repo.update_all(from(row in Call, where: row.public_id == ^call.id),
      set: [state: :ended, ended_at: @created]
    )

    {:ok, ended} = Calls.fetch_call(c.tenant, call.id, c.options)
    assert {:ok, ^ended} = hangup(c, call.id)
    assert ended.hangup_requested_at == nil
    assert {:error, :not_found} = hangup(c, Ecto.UUID.generate())
    assert {:error, :not_found} = hangup(c, "not-a-call")
    original = prepare(c)
    canonical_id = "abcdefab-cdef-4abc-8def-abcdefabcdef"

    Repo.update_all(from(row in Call, where: row.public_id == ^original.id),
      set: [public_id: canonical_id]
    )

    {:ok, untouched} = Calls.fetch_call(c.tenant, canonical_id, c.options)
    assert {:error, :not_found} = hangup(c, String.upcase(untouched.id))
    assert {:ok, ^untouched} = Calls.fetch_call(c.tenant, untouched.id, c.options)

    assert {:error, :not_found} =
             CallStore.request_call_hangup(Repo, "BBBBBBBBBBBBBBBB", call.id, @requested)

    assert {:error, :invalid_call_hangup} = hangup(c, prepare(c).id, DateTime.add(@created, -1))
  end

  defp prepare(c) do
    {:ok, call} = Calls.claim_call(c.actor, c.tenant, c.spec, %{}, nil, nil, c.options)
    call
  end

  defp hangup(c, id, now \\ @requested),
    do:
      Calls.request_call_hangup(
        c.actor,
        c.tenant,
        id,
        Keyword.put(c.options, :now, now)
      )

  defp scope(c, token),
    do: %{tenant_key: c.tenant, call_id: token.call_id, participant_key: token.participant_key}

  defp source,
    do: %{
      schema_version: "20261004.01",
      incoming_call: %{caller: "caller", handled_by: "assistant"},
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{type: "agent", prompt: "Help."}
      }
    }
end
