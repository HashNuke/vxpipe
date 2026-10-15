defmodule Vxpipe.Gateway.CallHangupTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.CreateRoom
  alias Vxpipe.Calls.{PreparedCall, Principal}
  alias Vxpipe.Gateway.{CallCleanup, CallCleanupSupervisor, CallHangup}

  @tenant "AAAAAAAAAAAAAAAA"
  @now ~U[2026-10-15 16:00:00Z]

  setup do
    call =
      struct(PreparedCall,
        id: "call",
        tenant_key: @tenant,
        state: :prepared,
        room_id: "room",
        created_at: @now,
        hangup_requested_at: nil
      )

    repository = start_supervised!({Agent, fn -> call end})
    actor = %Principal{tenant_key: @tenant, api_key_id: "key", scopes: MapSet.new([:calls])}

    options = [
      call_repository: {__MODULE__, {repository, self()}},
      now: @now,
      cleanup_reconciler: self()
    ]

    %{actor: actor, repository: repository, options: options}
  end

  test "prepared and already-ended calls return terminal evidence without runtime wake", c do
    assert {:ok, %{call_id: "call", status: "ended"}} = request(c)
    assert_receive :intent_persisted
    assert {:ok, %{call_id: "call", status: "ended"}} = request(c)
    assert_receive :intent_persisted
    refute_receive {:"$gen_cast", :wake}
  end

  test "authorization and storage failure precede all runtime actions", c do
    denied = %{c.actor | scopes: MapSet.new([:admin])}
    assert {:error, :not_authorized} = CallHangup.request(denied, @tenant, "call", c.options)

    assert {:error, :tenant_access_forbidden} =
             CallHangup.request(c.actor, "BBBBBBBBBBBBBBBB", "call", c.options)

    assert {:error, :not_found} = CallHangup.request(c.actor, @tenant, "missing", c.options)
    refute_receive :intent_persisted
    refute_receive {:"$gen_cast", :wake}
  end

  test "verified managed ownership accepts exact shutdown while owned resources drain", c do
    {binding, tracker} = managed(c)
    assert {:ok, _} = CallCleanup.observe(tracker)
    worker = start_supervised!({Task, fn -> receive do: (:finish -> :ok) end})
    assert :ok = CallCleanup.register(tracker, :session, worker)
    assert {:ok, %{call_id: "call", status: "ending"}} = request(c)
    assert_receive :intent_persisted
    assert_receive {:"$gen_cast", :wake}
    assert_receive {:call_cleanup_changed, ^tracker, %{engine_outcome: :complete}}, 1_000
    assert {:ok, %{status: "ending"}} = request(c)
    assert %{binding: ^binding, status: :pending} = CallCleanup.snapshot(tracker)
  end

  test "missing tracker cannot be reconstructed even when exact room termination is safe", c do
    {binding, tracker} = managed(c)
    :ok = DynamicSupervisor.terminate_child(CallCleanupSupervisor, tracker)
    assert {:error, :call_hangup_unknown} = request(c)
    assert_receive :intent_persisted
    assert {:error, :not_found} = CallCleanupSupervisor.lookup(binding)
    assert %DateTime{} = Agent.get(c.repository, & &1.hangup_requested_at)
  end

  test "unverified and unbound calls remain unknown without stopping a replacement", c do
    {binding, tracker} = managed(c)
    update(c, incarnation_binding_verified: false)
    assert {:error, :call_hangup_unknown} = request(c)
    assert %{engine_outcome: :pending} = CallCleanup.snapshot(tracker)
    update(c, incarnation_binding_verified: true, incarnation_id: "stale")
    assert {:error, :call_hangup_unknown} = request(c)
    assert %{engine_outcome: :pending} = CallCleanup.snapshot(tracker)
    update(c, incarnation_id: nil)
    assert {:error, :call_hangup_unknown} = request(c)
    assert {:ok, ^tracker} = CallCleanupSupervisor.lookup(binding)
  end

  test "unknown owned cleanup is never reported as accepted completion", c do
    {_binding, tracker} = managed(c)
    assert {:ok, _} = CallCleanup.observe(tracker)
    worker = start_supervised!({Task, fn -> receive do: (:finish -> :ok) end})
    :ok = CallCleanup.register(tracker, :session, worker)
    :ok = CallCleanup.acknowledge(tracker, worker, :unknown)
    assert %{status: :open, uncertain?: true} = CallCleanup.snapshot(tracker)
    assert {:error, :call_hangup_unknown} = request(c)
    assert_receive {:call_cleanup_changed, ^tracker, %{status: :unknown}}, 1_000
  end

  test "durable completion proof replays without recreating a tracker", c do
    update(c,
      state: :failed,
      incarnation_id: "retired",
      incarnation_binding_verified: true,
      gateway_cleanup_required: true,
      gateway_cleanup_completed_at: @now
    )

    assert {:ok, %{call_id: "call", status: "ended"}} = request(c)
    assert_receive {:completion_replayed, @now}
  end

  def request_call_hangup({repository, owner}, tenant, id, now) do
    Agent.get_and_update(repository, fn call ->
      if call.tenant_key == tenant and call.id == id do
        changed =
          cond do
            call.state == :ended ->
              call

            call.state == :prepared ->
              %{call | state: :ended, ended_at: now, hangup_requested_at: now}

            true ->
              %{call | hangup_requested_at: call.hangup_requested_at || now}
          end

        send(owner, :intent_persisted)
        {{:ok, changed}, changed}
      else
        {{:error, :not_found}, call}
      end
    end)
  end

  def fetch_call({repository, _}, tenant, id) do
    Agent.get(repository, fn call ->
      if call.tenant_key == tenant and call.id == id, do: {:ok, call}, else: {:error, :not_found}
    end)
  end

  def complete_call_cleanup({repository, owner}, binding, at) do
    send(owner, {:completion_replayed, at})

    Agent.get_and_update(repository, fn call ->
      if call.id == binding.call_id and call.incarnation_id == binding.incarnation_id do
        ended = %{call | state: :ended, ended_at: at}
        {{:ok, ended}, ended}
      else
        {{:error, :not_found}, call}
      end
    end)
  end

  defp request(c), do: CallHangup.request(c.actor, @tenant, "call", c.options)
  defp update(c, values), do: Agent.update(c.repository, &struct!(&1, values))

  defp managed(c) do
    {:ok, command} =
      CreateRoom.new(
        tenant_id: @tenant,
        actor_id: "test",
        deadline: DateTime.add(DateTime.utc_now(), 60)
      )

    {:ok, room} = CallEngine.create_room(command)

    binding = %{
      tenant_key: @tenant,
      call_id: "call",
      room_id: room.room_id,
      incarnation_id: room.incarnation_id
    }

    {:ok, tracker} = CallCleanupSupervisor.start_new(binding)

    update(c,
      state: :running,
      room_id: room.room_id,
      incarnation_id: room.incarnation_id,
      incarnation_binding_verified: true,
      gateway_cleanup_required: true
    )

    on_exit(fn ->
      CallEngine.end_call(@tenant, room.room_id, room.incarnation_id)

      case CallCleanupSupervisor.lookup(binding) do
        {:ok, pid} -> DynamicSupervisor.terminate_child(CallCleanupSupervisor, pid)
        _ -> :ok
      end
    end)

    {binding, tracker}
  end
end
