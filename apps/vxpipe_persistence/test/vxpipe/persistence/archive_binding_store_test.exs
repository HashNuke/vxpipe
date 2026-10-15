defmodule Vxpipe.Persistence.ArchiveBindingStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, CallFact, VariableSnapshot}
  alias Vxpipe.Persistence.{ArchiveStore, CallSpecStore, CallStore, CredentialStore, Repo}
  alias Vxpipe.Persistence.Schema.Call
  alias Vxpipe.Persistence.Schema.CallFact, as: StoredFact
  alias Vxpipe.Persistence.Schema.VariableSnapshot, as: StoredSnapshot

  @now ~U[2026-10-15 16:00:00.000000Z]

  setup do
    options = [
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      registries: %{host_tools: %{}},
      now: @now
    ]

    {:ok, tenant, key} = Administration.bootstrap_tenant("Archive binding", [:calls], options)
    {:ok, actor} = Calls.authenticate(tenant.key, key.secret, :calls, options)

    source = %{
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

    {:ok, draft} = Calls.save_call_spec(tenant.key, source, options)
    {:ok, published} = Calls.publish_call_spec(tenant.key, draft.call_spec_id, 1, options)

    {:ok, call} =
      Calls.claim_call(actor, tenant.key, published.call_spec_id, %{}, nil, nil, options)

    {:ok, token} = Calls.issue_call_join_token(actor, tenant.key, call.id, nil, options)
    scope = %{tenant_key: tenant.key, call_id: call.id, participant_key: token.participant_key}
    {:ok, claim} = Calls.claim_join_token(token.secret, scope, options)
    %{call: claim.call, claim: claim, options: options}
  end

  for first <- [:fact, :snapshot] do
    @first first
    test "#{first} anchors both archive streams before a started projection", %{call: call} do
      first = record(@first, call, "original")
      other = if @first == :fact, do: :snapshot, else: :fact
      assert {:ok, ^first} = store(first)
      anchored = Repo.get_by!(Call, public_id: call.id)
      assert anchored.incarnation_id == "original"
      assert anchored.incarnation_binding_verified
      assert {:error, :call_incarnation_mismatch} = store(record(other, call, "replacement"))
      second = record(other, call, "original")
      assert {:ok, ^second} = store(second)
      assert {:ok, ^first} = store(first)
      stored = Repo.get_by!(Call, public_id: call.id)
      assert stored.state == :admitting and stored.started_at == nil
    end

    test "#{first} cannot anchor or append another room", %{call: call} do
      invalid = %{record(@first, call, "original") | room_id: Ecto.UUID.generate()}
      assert {:error, :call_room_mismatch} = store(invalid)
      assert Repo.get_by!(Call, public_id: call.id).incarnation_id == nil
      assert Repo.aggregate(StoredFact, :count) == 0
      assert Repo.aggregate(StoredSnapshot, :count) == 0
    end

    test "#{first} rejects conflicting legacy history across streams", %{call: call} = context do
      fact = record(:fact, call, "original")
      snapshot = record(:snapshot, call, "original")
      assert {:ok, ^fact} = store(fact)
      assert {:ok, ^snapshot} = store(snapshot)
      stored = Repo.get_by!(Call, public_id: call.id)
      legacy = Repo.get_by!(StoredSnapshot, call_id: stored.id)
      Repo.update!(Ecto.Changeset.change(legacy, incarnation_id: "conflicting-legacy"))

      for legacy_anchor <- [nil, "original"] do
        Repo.update!(
          Ecto.Changeset.change(Repo.get!(Call, stored.id),
            incarnation_id: legacy_anchor,
            incarnation_binding_verified: false
          )
        )

        assert {:error, :call_incarnation_mismatch} =
                 Calls.bind_call_admission(context.claim, "original", context.options)

        assert {:error, :call_incarnation_mismatch} = store(record(@first, call, "original"))
        unchanged = Repo.get!(Call, stored.id)
        assert unchanged.incarnation_id == legacy_anchor
        refute unchanged.incarnation_binding_verified
      end
    end
  end

  test "a rejected first archive insert rolls back the binding", %{call: call} do
    invalid = %{record(:fact, call, "invalid") | sequence: 0}
    assert {:error, :call_fact_insert_failed} = store(invalid)
    unchanged = Repo.get_by!(Call, public_id: call.id)
    assert unchanged.incarnation_id == nil
    refute unchanged.incarnation_binding_verified
  end

  defp record(:fact, call, incarnation) do
    {:ok, fact} =
      CallFact.new(
        identity(call, incarnation) ++
          [
            id: "opening",
            kind: :room_opened,
            sequence: 1,
            payload: %{}
          ]
      )

    fact
  end

  defp record(:snapshot, call, incarnation) do
    {:ok, snapshot} =
      VariableSnapshot.new(
        identity(call, incarnation) ++
          [
            id: "baseline",
            kind: :baseline,
            global_revision: 0,
            sections: %{}
          ]
      )

    snapshot
  end

  defp identity(call, incarnation) do
    [
      tenant_key: call.tenant_key,
      call_id: call.id,
      room_id: call.room_id,
      incarnation_id: incarnation,
      occurred_at: @now,
      source_policy: %{"revision" => 0, "save_transcripts" => true}
    ]
  end

  defp store(%CallFact{} = fact), do: ArchiveStore.store_call_fact(Repo, fact)

  defp store(%VariableSnapshot{} = snapshot),
    do: ArchiveStore.store_variable_snapshot(Repo, snapshot)
end
