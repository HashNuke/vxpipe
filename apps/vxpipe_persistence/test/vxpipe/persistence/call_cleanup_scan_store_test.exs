defmodule Vxpipe.Persistence.CallCleanupScanStoreTest do
  use Vxpipe.Persistence.DataCase, async: false
  import Ecto.Query
  alias Vxpipe.Calls
  alias Vxpipe.Calls.Administration
  alias Vxpipe.Persistence.{CallSpecStore, CallStore, CredentialStore, Repo}
  alias Vxpipe.Persistence.Schema.Call

  @now ~U[2026-10-15 16:00:00.000000Z]

  setup do
    options = [
      credential_repository: {CredentialStore, Repo},
      call_spec_repository: {CallSpecStore, Repo},
      call_repository: {CallStore, Repo},
      registries: %{host_tools: %{}},
      now: @now
    ]

    {:ok, tenant, key} = Administration.bootstrap_tenant("Cleanup scan", [:calls], options)
    {:ok, actor} = Calls.authenticate(tenant.key, key.secret, :calls, options)
    {:ok, draft} = Calls.save_call_spec(tenant.key, source(), options)
    {:ok, published} = Calls.publish_call_spec(tenant.key, draft.call_spec_id, 1, options)
    %{tenant: tenant.key, actor: actor, spec: published.call_spec_id, options: options}
  end

  test "scans unresolved intent and managed cleanup without loading plans or secrets", c do
    _dormant = call(c, [])
    unbound = call(c, hangup_requested_at: @now, state: :admitting)
    normal = call(c, managed())
    failed = call(c, Keyword.put(managed(), :state, :failed))
    completed = call(c, Keyword.put(managed(), :gateway_cleanup_completed_at, @now))
    retry = call(c, managed() ++ [gateway_cleanup_completed_at: @now, hangup_requested_at: @now])

    _ended =
      call(c, Keyword.merge(managed(), state: :ended, ended_at: @now, hangup_requested_at: @now))

    # Recovery needs only ownership, including when an archived plan cannot decode.
    Repo.update_all(from(row in Call, where: row.public_id == ^normal.id),
      set: [resolved_plan: <<0>>]
    )

    assert {:ok, %{items: items, next_cursor: nil}} = Calls.scan_call_cleanup(nil, 100, c.options)
    assert Enum.map(items, & &1.call_id) == [unbound.id, normal.id, failed.id, retry.id]
    assert Enum.all?(items, &(&1.tenant_key == c.tenant))
    assert Enum.map(items, & &1.incarnation_id) == [nil, "owner", "owner", "owner"]
    assert Enum.map(items, & &1.gateway_cleanup_required) == [false, true, true, true]
    assert Enum.map(items, & &1.gateway_cleanup_completed_at) == [nil, nil, nil, @now]

    assert Enum.all?(
             items,
             &(Enum.sort(Map.keys(&1)) ==
                 Enum.sort([
                   :id,
                   :tenant_key,
                   :call_id,
                   :room_id,
                   :incarnation_id,
                   :incarnation_binding_verified,
                   :hangup_requested_at,
                   :gateway_cleanup_required,
                   :gateway_cleanup_completed_at
                 ]))
           )

    refute Enum.any?(items, &(&1.call_id == completed.id))
  end

  test "finite keyset cycles pass unresolved older work and defer new inserts to next cycle", c do
    calls = for _ <- 1..5, do: call(c, managed())

    assert {:ok, %{items: first, next_cursor: cursor}} =
             Calls.scan_call_cleanup(nil, 2, c.options)

    assert Enum.map(first, & &1.call_id) == Enum.map(Enum.take(calls, 2), & &1.id)
    late = call(c, managed())
    # Completion/removal between pages must not make offset pagination skip work.
    first_id = hd(calls).id

    Repo.update_all(from(row in Call, where: row.public_id == ^first_id),
      set: [gateway_cleanup_completed_at: @now]
    )

    assert {:ok, %{items: second, next_cursor: next}} =
             Calls.scan_call_cleanup(cursor, 2, c.options)

    assert Enum.map(second, & &1.call_id) == Enum.map(Enum.slice(calls, 2, 2), & &1.id)
    assert {:ok, %{items: last, next_cursor: nil}} = Calls.scan_call_cleanup(next, 2, c.options)
    assert Enum.map(last, & &1.call_id) == [List.last(calls).id]

    assert {:ok, %{items: restarted, next_cursor: nil}} =
             Calls.scan_call_cleanup(nil, 100, c.options)

    assert Enum.map(restarted, & &1.call_id) == Enum.map(tl(calls), & &1.id) ++ [late.id]
  end

  test "an empty cycle ends and bounds are checked at the storage boundary", c do
    assert {:ok, %{items: [], next_cursor: nil}} = Calls.scan_call_cleanup(nil, 1, c.options)
    assert {:error, :invalid_cleanup_scan} = CallStore.scan_call_cleanup(Repo, nil, 101)

    assert {:error, :invalid_cleanup_scan} =
             CallStore.scan_call_cleanup(Repo, %{after_id: 4, through_id: 2}, 10)
  end

  defp managed,
    do: [
      state: :admitting,
      incarnation_id: "owner",
      incarnation_binding_verified: true,
      gateway_cleanup_required: true
    ]

  defp call(c, changes) do
    {:ok, call} = Calls.claim_call(c.actor, c.tenant, c.spec, %{}, nil, nil, c.options)

    if changes != [],
      do: Repo.update_all(from(row in Call, where: row.public_id == ^call.id), set: changes)

    call
  end

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
