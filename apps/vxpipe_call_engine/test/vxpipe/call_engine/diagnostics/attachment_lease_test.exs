defmodule Vxpipe.CallEngine.Diagnostics.AttachmentLeaseTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.AttachmentLease

  test "expired and cancelled attempts cannot be adopted or dispatch work" do
    clock = :atomics.new(1, signed: true)
    gate = AttachmentLease.gate(1)

    {:ok, lease} =
      AttachmentLease.reserve(gate, self(),
        timeout_ms: 100,
        clock: fn -> :atomics.get(clock, 1) end
      )

    assert AttachmentLease.current?(lease)
    :atomics.put(clock, 1, 100)
    refute AttachmentLease.adopt(lease)
    refute AttachmentLease.current?(lease)

    assert {:error, :unavailable} =
             AttachmentLease.operation(lease, fn -> flunk("expired work dispatched") end)

    AttachmentLease.finish(lease)
    assert AttachmentLease.pending(gate) == 0
    {:ok, next} = AttachmentLease.reserve(gate, self())
    AttachmentLease.cancel(next)
    refute AttachmentLease.adopt(next)
    AttachmentLease.finish(next)
    assert AttachmentLease.pending(gate) == 0
  end

  test "adoption outlives startup but finishing forbids further admission" do
    clock = :atomics.new(1, signed: true)
    gate = AttachmentLease.gate(1)
    {:ok, lease} = AttachmentLease.reserve(gate, self(), clock: fn -> :atomics.get(clock, 1) end)
    assert AttachmentLease.adopt(lease)
    AttachmentLease.finish(lease)
    :atomics.put(clock, 1, 1_000)
    assert AttachmentLease.current?(lease)
    assert AttachmentLease.pending(gate) == 0

    assert {:error, :unavailable} =
             AttachmentLease.operation(lease, fn -> flunk("finished admission dispatched") end)

    AttachmentLease.cancel(lease)
    refute AttachmentLease.current?(lease)
    refute AttachmentLease.adopt(lease)
    AttachmentLease.finish(lease)
    assert AttachmentLease.pending(gate) == 0
  end

  test "known outer failure cannot release an unresolved nested admission" do
    parent = self()
    tasks = start_supervised!({Task.Supervisor, []})
    gate = AttachmentLease.gate(1)
    {:ok, lease} = AttachmentLease.reserve(gate, self())

    {:ok, nested} =
      AttachmentLease.operation(lease, fn ->
        Task.Supervisor.start_child(tasks, fn ->
          AttachmentLease.operation(lease, fn ->
            send(parent, :nested_started)

            receive do
              :finish -> :ok
            end
          end)
        end)
      end)

    assert_receive :nested_started
    monitor = Process.monitor(nested)
    AttachmentLease.cancel(lease)
    AttachmentLease.finish(lease)
    assert AttachmentLease.pending(gate) == 1
    assert {:error, :unavailable} = AttachmentLease.reserve(gate, self())
    send(nested, :finish)
    assert_receive {:DOWN, ^monitor, :process, ^nested, :normal}
    assert AttachmentLease.pending(gate) == 0
    AttachmentLease.finish(lease)
    assert AttachmentLease.pending(gate) == 0
  end

  test "killed admission retains bounded debt until its owning pool is replaced" do
    parent = self()
    tasks = start_supervised!({Task.Supervisor, []})
    gate = AttachmentLease.gate(1)
    {:ok, lease} = AttachmentLease.reserve(gate, self())

    {:ok, helper} =
      Task.Supervisor.start_child(tasks, fn ->
        AttachmentLease.operation(lease, fn ->
          send(parent, :admission_started)

          receive do
            :never -> :ok
          end
        end)
      end)

    assert_receive :admission_started
    monitor = Process.monitor(helper)
    AttachmentLease.cancel(lease)
    Process.exit(helper, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^helper, :killed}
    AttachmentLease.finish(lease)
    assert AttachmentLease.pending(gate) == 1
    for _ <- 1..20, do: assert({:error, :unavailable} = AttachmentLease.reserve(gate, self()))
    assert AttachmentLease.pending(gate) == 1
  end
end
