defmodule Vxpipe.CallEngine.Diagnostics.AdmissionSupervisorTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.{AdmissionSupervisor, AttachmentLease, SourceAdmission}

  setup do
    gate = AttachmentLease.gate(1)
    admission = via()
    options = [name: via(), admission: admission, gate: gate]
    workers = via()
    call = via()

    children = [
      {AdmissionSupervisor, options},
      {DynamicSupervisor, name: workers, strategy: :one_for_one},
      Supervisor.child_spec({Agent, fn -> :call_open end},
        id: :call,
        restart: :temporary,
        significant: true,
        start: {Agent, :start_link, [fn -> :call_open end, [name: call]]}
      )
    ]

    root =
      start_supervised!(%{
        id: :root,
        type: :supervisor,
        shutdown: :infinity,
        start:
          {Supervisor, :start_link,
           [children, [strategy: :one_for_one, auto_shutdown: :any_significant, name: via()]]}
      })

    %{
      gate: gate,
      options: options,
      root: root,
      workers: workers,
      call: call,
      admission: admission
    }
  end

  test "restarting the optional subtree does not reset capacity over a surviving room worker",
       c do
    {:ok, lease} = SourceAdmission.reserve(c.admission, self())
    spec = Supervisor.child_spec({Agent, fn -> :source end}, restart: :temporary)
    {:ok, worker} = SourceAdmission.start_worker(c.admission, lease, c.workers, spec)
    :ok = SourceAdmission.adopt(c.admission, lease)
    :ok = :sys.suspend(worker)

    try do
      subtree = GenServer.whereis(Keyword.fetch!(c.options, :name))
      previous = GenServer.whereis(c.admission)
      monitor = Process.monitor(previous)
      Process.exit(previous, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^previous, :killed}
      _replacement = replacement(subtree, previous, System.monotonic_time(:millisecond) + 1_000)
      assert {:error, :capacity_unavailable} = SourceAdmission.reserve(c.admission, self())

      child = {AdmissionSupervisor, Keyword.fetch!(c.options, :name)}
      :ok = Supervisor.terminate_child(c.root, child)
      assert {:error, :unavailable} = SourceAdmission.reserve(c.admission, self())
      # Temporary subtrees are removed on exit; an explicit replacement must reuse its gate.
      assert {:ok, _} = Supervisor.start_child(c.root, {AdmissionSupervisor, c.options})
      assert {:error, :capacity_unavailable} = SourceAdmission.reserve(c.admission, self())
      assert AttachmentLease.pending(c.gate) == 1
      assert Agent.get(c.call, & &1) == :call_open
    after
      :sys.resume(worker)
    end
  end

  test "exhausted admission restarts leave the call open and admission unavailable", c do
    subtree = GenServer.whereis(Keyword.fetch!(c.options, :name))
    monitor = Process.monitor(subtree)

    for _ <- 1..2 do
      previous = GenServer.whereis(c.admission)
      child_monitor = Process.monitor(previous)
      Process.exit(previous, :kill)
      assert_receive {:DOWN, ^child_monitor, :process, ^previous, :killed}
      assert is_pid(replacement(subtree, previous, System.monotonic_time(:millisecond) + 1_000))
    end

    Process.exit(GenServer.whereis(c.admission), :kill)
    assert_receive {:DOWN, ^monitor, :process, ^subtree, :shutdown}
    assert Agent.get(c.call, & &1) == :call_open
    assert {:error, :unavailable} = SourceAdmission.reserve(c.admission, self())
  end

  test "a fresh root gate follows confirmed teardown of the old room workers", c do
    {:ok, lease} = SourceAdmission.reserve(c.admission, self())

    {:ok, worker} =
      SourceAdmission.start_worker(
        c.admission,
        lease,
        c.workers,
        Supervisor.child_spec({Agent, fn -> :source end}, restart: :temporary)
      )

    :ok = SourceAdmission.adopt(c.admission, lease)
    monitor = Process.monitor(worker)
    assert :ok = stop_supervised(:root)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :shutdown}
    fresh = AttachmentLease.gate(1)
    assert fresh.counter != c.gate.counter
    next = start_supervised!({AdmissionSupervisor, name: via(), admission: via(), gate: fresh})
    [{SourceAdmission, tracker, _, _}] = Supervisor.which_children(next)
    assert {:ok, _lease} = SourceAdmission.reserve(tracker, self())
  end

  defp replacement(supervisor, previous, deadline) do
    [{SourceAdmission, pid, _, _}] = Supervisor.which_children(supervisor)

    cond do
      is_pid(pid) and pid != previous ->
        pid

      System.monotonic_time(:millisecond) < deadline ->
        replacement(supervisor, previous, deadline)

      true ->
        flunk("admission tracker did not restart")
    end
  end

  defp via, do: {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {__MODULE__, make_ref()}}}
end
