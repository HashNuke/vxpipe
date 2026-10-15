defmodule Vxpipe.Gateway.Telephony.CarrierCleanupTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.CreateRoom
  alias Vxpipe.CallEngine.Telephony.OutboundLegRequest
  alias Vxpipe.Gateway.{CallCleanup, CallCleanupSupervisor, TestFinalUsageRepository}
  alias Vxpipe.Gateway.Telephony.{CarrierCleanup, ConfiguredService, LegUsage}

  setup do
    {:ok, command} =
      CreateRoom.new(
        tenant_id: "carrier-cleanup",
        actor_id: "test",
        deadline: DateTime.add(DateTime.utc_now(), 60, :second)
      )

    {:ok, room} = CallEngine.create_room(command)

    binding = %{
      tenant_key: command.tenant_id,
      call_id: "call-#{room.room_id}",
      room_id: room.room_id,
      incarnation_id: room.incarnation_id
    }

    on_exit(fn ->
      CallEngine.end_call(binding.tenant_key, binding.room_id, binding.incarnation_id)

      case CallCleanupSupervisor.lookup(binding) do
        {:ok, tracker} -> DynamicSupervisor.terminate_child(CallCleanupSupervisor, tracker)
        _ -> :ok
      end
    end)

    %{binding: binding, usage: usage(binding)}
  end

  test "attachment requires existing exact membership and never recreates a missing tracker", c do
    assert {:error, :cleanup_unavailable, detached} =
             CarrierCleanup.attach(c.binding, :outgoing_leg, c.binding)

    assert CarrierCleanup.status(detached) == :unavailable

    assert {:error, :not_found} = CallCleanupSupervisor.lookup(c.binding)
    {:ok, tracker} = CallCleanupSupervisor.start_new(c.binding)
    wrong = %{c.binding | call_id: "another-call"}

    assert {:error, :invalid_cleanup_binding} =
             CarrierCleanup.attach(c.binding, :outgoing_leg, wrong)

    assert CallCleanup.snapshot(tracker).resources == %{}
    assert {:ok, cleanup} = CarrierCleanup.attach(c.binding, :outgoing_leg, c.binding)
    assert CarrierCleanup.status(cleanup) == :idle
    owner = self()

    assert %{kind: :outgoing_leg, owner: ^owner, acknowledgement: :pending} =
             Map.fetch!(CallCleanup.snapshot(tracker).resources, owner)
  end

  test "an incoming owner adopts its atomically seeded membership after sealing", c do
    {:ok, tracker} = CallCleanupSupervisor.start_new(c.binding, {:incoming_leg, self()})
    :ok = CallCleanup.seal(tracker)
    assert {:ok, _} = CarrierCleanup.attach(c.binding, :incoming_leg, c.binding)

    assert {:error, :cleanup_unavailable, detached} =
             CarrierCleanup.attach(c.binding, :outgoing_leg, c.binding)

    assert CarrierCleanup.status(detached) == :unavailable

    assert map_size(CallCleanup.snapshot(tracker).resources) == 1
  end

  test "unavailable attachment retains exact final storage without creating membership", c do
    options = [
      calls_options: [usage_repository: {TestFinalUsageRepository, {self(), &{:ok, &1}}}]
    ]

    assert {:error, :cleanup_unavailable, cleanup} =
             CarrierCleanup.attach(c.binding, :outgoing_leg, c.binding, options)

    final = LegUsage.fail(c.usage, :unknown)
    refute CarrierCleanup.final_usage_stored?(cleanup, final)
    assert {:ok, cleanup} = CarrierCleanup.begin_final(cleanup, final)
    assert_receive {reference, :ok}
    assert {:handled, cleanup} = CarrierCleanup.handle_info(cleanup, {reference, :ok})
    refute CarrierCleanup.final_usage_stored?(cleanup, final)
    assert_receive {:DOWN, ^reference, :process, task, :normal}

    assert {:handled, cleanup} =
             CarrierCleanup.handle_info(cleanup, {:DOWN, reference, :process, task, :normal})

    assert CarrierCleanup.final_usage_stored?(cleanup, final)
    assert CarrierCleanup.status(cleanup) == :unavailable

    for observation <- final.observations,
        do: assert_receive({:stored_carrier_usage, ^observation})

    assert {:error, :cleanup_unavailable, ^cleanup} =
             CarrierCleanup.acknowledge(cleanup, final, :carrier_ended, true)

    assert {:error, :not_found} = CallCleanupSupervisor.lookup(c.binding)
  end

  test "invalid attachment never returns detached persistence authority", c do
    wrong = %{c.binding | room_id: "another-room"}

    assert {:error, :invalid_cleanup_binding} =
             CarrierCleanup.attach(c.binding, :outgoing_leg, wrong)

    for options <- [
          [timeout_ms: 0],
          [calls_options: :invalid],
          [calls_options: [:malformed]],
          [:malformed]
        ] do
      assert {:error, :invalid_cleanup_options} =
               CarrierCleanup.attach(c.binding, :outgoing_leg, c.binding, options)
    end

    assert {:error, :cleanup_unavailable} =
             CarrierCleanup.attach(c.binding, :unsupported, c.binding)

    refute_received {:stored_carrier_usage, _}
  end

  test "unknown usage persists but acknowledgement needs independent proof and actual task DOWN",
       c do
    {cleanup, tracker} = attached(c)
    final = LegUsage.fail(c.usage, :unknown)
    assert {:ok, cleanup} = CarrierCleanup.begin_final(cleanup, final)
    assert_receive {reference, :ok}
    assert is_reference(reference)
    assert {:handled, cleanup} = CarrierCleanup.handle_info(cleanup, {reference, :ok})

    assert {:error, :cleanup_not_ready, ^cleanup} =
             CarrierCleanup.acknowledge(cleanup, final, :carrier_ended, true)

    assert_receive {:DOWN, ^reference, :process, task, :normal}

    assert {:handled, cleanup} =
             CarrierCleanup.handle_info(cleanup, {:DOWN, reference, :process, task, :normal})

    assert CarrierCleanup.status(cleanup) == :stored

    for observation <- final.observations,
        do: assert_receive({:stored_carrier_usage, ^observation})

    assert {:error, :cleanup_not_ready, ^cleanup} =
             CarrierCleanup.acknowledge(cleanup, final, :unknown, true)

    assert {:error, :cleanup_not_ready, ^cleanup} =
             CarrierCleanup.acknowledge(cleanup, final, :carrier_ended, false)

    assert {:ok, cleanup} = CarrierCleanup.acknowledge(cleanup, final, :carrier_ended, true)
    assert CarrierCleanup.status(cleanup) == :acknowledged

    assert Map.fetch!(CallCleanup.snapshot(tracker).resources, self()).acknowledgement ==
             :complete
  end

  test "partial persistence retries the original complete batch without releasing ownership", c do
    failures = start_supervised!({Agent, fn -> 0 end})
    final = LegUsage.fail(c.usage, :failed)

    result = fn observation ->
      attempt = Agent.get_and_update(failures, fn count -> {count, count + 1} end)
      if attempt == 1, do: {:error, :unavailable}, else: {:ok, observation}
    end

    {cleanup, tracker} = attached(c, result, retry_ms: 0)
    {:ok, cleanup} = CarrierCleanup.begin_final(cleanup, final)
    cleanup = advance_until(cleanup, :retrying)
    assert Map.fetch!(CallCleanup.snapshot(tracker).resources, self()).acknowledgement == :pending
    cleanup = advance_until(cleanup, :stored)
    [first, second] = final.observations

    for observation <- [first, second] ++ final.observations,
        do: assert_receive({:stored_carrier_usage, ^observation})

    assert {:ok, _} = CarrierCleanup.acknowledge(cleanup, final, :not_submitted, true)
  end

  test "timeout drains the persistence task before retrying the unchanged batch", c do
    observer = self()
    attempts = start_supervised!({Agent, fn -> 0 end})

    result = fn observation ->
      count = Agent.get_and_update(attempts, fn n -> {n, n + 1} end)

      if count == 0 do
        send(observer, {:blocked_store, self()})
        receive do: (:release -> {:ok, observation})
      else
        {:ok, observation}
      end
    end

    {cleanup, _} = attached(c, result, timeout_ms: 100, retry_ms: 0)
    final = LegUsage.fail(c.usage, :cancelled)
    {:ok, cleanup} = CarrierCleanup.begin_final(cleanup, final)
    assert_receive {:blocked_store, worker}
    on_exit(fn -> send(worker, :release) end)
    assert CarrierCleanup.status(cleanup) == :storing
    assert_receive {:DOWN, reference, :process, ^worker, :killed}, 1_000

    assert {:handled, cleanup} =
             CarrierCleanup.handle_info(cleanup, {:DOWN, reference, :process, worker, :killed})

    assert CarrierCleanup.status(cleanup) == :retrying
    cleanup = advance_until(cleanup, :stored)
    assert {:ok, _} = CarrierCleanup.acknowledge(cleanup, final, :carrier_ended, true)
  end

  test "storage deadline survives immediate death of the original owner", c do
    {:ok, tracker} = CallCleanupSupervisor.start_new(c.binding)
    observer = self()

    owner =
      start_supervised!(
        {Task,
         fn ->
           receive do: (:begin -> :ok)
           owner = self()

           result = fn _observation ->
             send(observer, {:orphaned_store, self()})
             Process.exit(owner, :kill)
             receive do: (:release -> {:error, :unavailable})
           end

           options = [
             timeout_ms: 100,
             calls_options: [usage_repository: {TestFinalUsageRepository, {observer, result}}]
           ]

           {:ok, cleanup} = CarrierCleanup.attach(c.binding, :outgoing_leg, c.binding, options)
           {:ok, _cleanup} = CarrierCleanup.begin_final(cleanup, LegUsage.fail(c.usage, :failed))
           receive do: (:finish -> :ok)
         end}
      )

    owner_monitor = Process.monitor(owner)
    send(owner, :begin)
    assert_receive {:orphaned_store, task}
    on_exit(fn -> send(task, :release) end)
    task_monitor = Process.monitor(task)
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, :killed}
    assert_receive {:DOWN, ^task_monitor, :process, ^task, :killed}, 1_000
    assert Map.fetch!(CallCleanup.snapshot(tracker).resources, owner).acknowledgement == :pending
  end

  test "stale persistence cannot acknowledge a replacement usage batch", c do
    {cleanup, _} = attached(c)
    final = LegUsage.fail(c.usage, :failed)
    {:ok, cleanup} = CarrierCleanup.begin_final(cleanup, final)
    cleanup = advance_until(cleanup, :stored)
    [first | rest] = final.observations
    changed = %{final | observations: [%{first | delivery_id: "different"} | rest]}
    assert {:error, :usage_changed, ^cleanup} = CarrierCleanup.begin_final(cleanup, changed)

    assert {:error, :cleanup_not_ready, ^cleanup} =
             CarrierCleanup.acknowledge(cleanup, changed, :not_submitted, true)

    assert {:ok, _} = CarrierCleanup.acknowledge(cleanup, final, :not_submitted, true)
  end

  test "tracker loss is exposed without manufacturing replacement membership", c do
    {cleanup, tracker} = attached(c)
    final = LegUsage.fail(c.usage, :failed)
    {:ok, cleanup} = CarrierCleanup.begin_final(cleanup, final)
    cleanup = advance_until(cleanup, :stored)
    Process.exit(tracker, :kill)
    assert_receive {:DOWN, reference, :process, ^tracker, :killed}

    assert {:handled, cleanup} =
             CarrierCleanup.handle_info(cleanup, {:DOWN, reference, :process, tracker, :killed})

    assert CarrierCleanup.status(cleanup) == :unavailable
    assert CarrierCleanup.final_usage_stored?(cleanup, final)
    [first | rest] = final.observations
    changed = %{final | observations: [%{first | delivery_id: "changed"} | rest]}
    refute CarrierCleanup.final_usage_stored?(cleanup, changed)
    refute CarrierCleanup.final_usage_stored?(cleanup, nil)
    refute CarrierCleanup.final_usage_stored?(cleanup, c.usage)
    observer = self()

    start_supervised!(
      {Task,
       fn ->
         send(observer, {:foreign_stored, CarrierCleanup.final_usage_stored?(cleanup, final)})
       end}
    )

    assert_receive {:foreign_stored, false}

    assert {:error, :cleanup_unavailable, ^cleanup} =
             CarrierCleanup.acknowledge(cleanup, final, :carrier_ended, true)

    assert {:error, :not_found} = CallCleanupSupervisor.lookup(c.binding)
  end

  test "only the original carrier owner can acknowledge persisted usage", c do
    {cleanup, tracker} = attached(c)
    final = LegUsage.fail(c.usage, :failed)
    {:ok, cleanup} = CarrierCleanup.begin_final(cleanup, final)
    cleanup = advance_until(cleanup, :stored)
    observer = self()

    start_supervised!(
      {Task,
       fn ->
         send(
           observer,
           {:foreign_ack, CarrierCleanup.acknowledge(cleanup, final, :not_submitted, true)}
         )
       end}
    )

    assert_receive {:foreign_ack, {:error, :invalid_cleanup_owner, _}}
    assert Map.fetch!(CallCleanup.snapshot(tracker).resources, self()).acknowledgement == :pending
    assert {:ok, _} = CarrierCleanup.acknowledge(cleanup, final, :not_submitted, true)
  end

  test "missing, nonterminal or differently anchored usage never enters persistence", c do
    {cleanup, _} = attached(c)
    assert {:error, :usage_not_final, ^cleanup} = CarrierCleanup.begin_final(cleanup, nil)
    assert {:error, :usage_not_final, ^cleanup} = CarrierCleanup.begin_final(cleanup, c.usage)
    final = LegUsage.fail(c.usage, :failed)
    wrong = %{final | attempt: %{final.attempt | room_id: "another-room"}}
    assert {:error, :invalid_usage_binding, ^cleanup} = CarrierCleanup.begin_final(cleanup, wrong)
    refute_received {:stored_carrier_usage, _}
  end

  defp attached(c, result \\ fn observation -> {:ok, observation} end, options \\ []) do
    {:ok, tracker} = CallCleanupSupervisor.start_new(c.binding)

    options =
      Keyword.put(options, :calls_options,
        usage_repository: {TestFinalUsageRepository, {self(), result}}
      )

    {:ok, cleanup} = CarrierCleanup.attach(c.binding, :outgoing_leg, c.binding, options)
    {cleanup, tracker}
  end

  defp advance_until(cleanup, wanted) do
    if CarrierCleanup.status(cleanup) == wanted do
      cleanup
    else
      message =
        receive do
          {reference, _result} = message when is_reference(reference) -> message
          {:DOWN, _, :process, _, _} = message -> message
          {:carrier_cleanup_retry, _} = message -> message
        after
          2_000 -> flunk("cleanup did not reach #{wanted}")
        end

      assert {:handled, next} = CarrierCleanup.handle_info(cleanup, message)
      advance_until(next, wanted)
    end
  end

  defp usage(binding) do
    {:ok, service} =
      ConfiguredService.new(
        id: "telnyx-primary",
        ingress_key: "usage-ingress",
        scope: {:tenant, binding.tenant_key},
        provider: :telnyx,
        provider_connection_id: "application",
        public_key: Base.encode64(:binary.copy(<<1>>, 32)),
        api_key: "synthetic",
        public_base_url: "https://voice.example.test",
        adapter: Vxpipe.Gateway.TestTelephonyAdapter
      )

    request = %OutboundLegRequest{
      tenant_id: binding.tenant_key,
      actor_id: "actor",
      call_id: binding.call_id,
      room_id: binding.room_id,
      incarnation_id: binding.incarnation_id,
      participant_id: "participant",
      service_id: "telnyx-primary",
      to: "+15550001001"
    }

    LegUsage.start_outgoing(request, service, "leg-usage",
      usage_clock: fn -> ~U[2026-10-15 12:00:00.000Z] end,
      usage_reporter: {Vxpipe.Gateway.TestUsageReporter, self()}
    )
  end
end
