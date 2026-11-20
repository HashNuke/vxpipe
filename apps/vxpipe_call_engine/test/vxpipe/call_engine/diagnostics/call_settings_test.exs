defmodule Vxpipe.CallEngine.Diagnostics.CallSettingsTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.Diagnostics.{CallSettings, CaptureHandoff, RoomSupervisor}

  setup do
    previous = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, previous)
    end)

    %{previous: previous}
  end

  test "each new room snapshots once; toggles do not change existing capture", c do
    store = start_supervised!({Agent, fn -> %{enabled: true, revision: 1} end})
    parent = self()

    loader = fn ->
      send(parent, :snapshot_read)
      {:ok, Agent.get(store, & &1)}
    end

    configure(c.previous, loader)
    options = RoomSupervisor.options(identity("first"), self(), [])
    assert_receive :snapshot_read
    settings = Keyword.fetch!(options, :settings)
    assert {:ok, handoff} = CaptureHandoff.new(self(), settings: settings)
    Agent.update(store, fn _ -> %{enabled: false, revision: 2} end)
    assert CaptureHandoff.current?(handoff)
    assert :ok = CaptureHandoff.offer(handoff, {:reset, 0, :partial_start, 0})
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = message
    assert {:ok, _, charge} = CaptureHandoff.message(handoff, message)
    CaptureHandoff.release(handoff, charge, :processed)
    refute_received :snapshot_read
    disabled = RoomSupervisor.options(identity("second"), self(), []) |> Keyword.fetch!(:settings)
    assert_receive :snapshot_read
    assert {:error, :unavailable} = CallSettings.grant(disabled)
    Agent.update(store, fn _ -> %{enabled: true, revision: 3} end)
    assert {:error, :unavailable} = CallSettings.grant(disabled)
    assert CaptureHandoff.current?(handoff)
    third = RoomSupervisor.options(identity("third"), self(), []) |> Keyword.fetch!(:settings)
    assert_receive :snapshot_read
    assert {:ok, {3, _}} = CallSettings.grant(third)
    assert {:ok, {1, _}} = CallSettings.grant(settings)
    refute_received :snapshot_read
  end

  test "failed call-start read stays disabled after storage recovers", c do
    configure(c.previous, fn -> {:error, :unavailable} end)
    settings = RoomSupervisor.options(identity("failed"), self(), []) |> Keyword.fetch!(:settings)
    configure(c.previous, fn -> {:ok, %{enabled: true, revision: 4}} end)
    assert {:error, :unavailable} = CallSettings.grant(settings)
    next = RoomSupervisor.options(identity("recovered"), self(), []) |> Keyword.fetch!(:settings)
    assert {:ok, {4, _}} = CallSettings.grant(next)
  end

  test "stalled snapshot is bounded and its worker is terminated", c do
    parent = self()

    configure(c.previous, fn ->
      send(parent, {:snapshot_task, self()})

      receive do
        :never -> {:ok, %{enabled: true, revision: 1}}
      end
    end)

    assert %{enabled: false} = CallSettings.capture()
    assert_receive {:snapshot_task, pid}
    monitor = Process.monitor(pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :noproc}
  end

  test "observer restart retains the call's original snapshot", c do
    parent = self()

    configure(c.previous, fn ->
      send(parent, :snapshot_read)
      {:ok, %{enabled: true, revision: 7}}
    end)

    options = RoomSupervisor.options(identity("restart"), self(), [])
    assert_receive :snapshot_read
    original = Keyword.fetch!(options, :settings)
    supervisor = start_supervised!({RoomSupervisor, options})
    configure(c.previous, fn -> flunk("an existing call reread its setting") end)
    service = Vxpipe.CallEngine.Diagnostics.RoomService
    assert :ok = Supervisor.terminate_child(supervisor, service)
    assert {:ok, restarted} = Supervisor.restart_child(supervisor, service)
    assert :sys.get_state(restarted).settings == original
    assert {:ok, {7, _}} = CallSettings.grant(original)
    refute_received :snapshot_read
  end

  test "malformed persisted values and loader errors remain disabled", c do
    for value <- [%{enabled: "true", revision: 1}, %{enabled: true, revision: -1}, nil] do
      configure(c.previous, fn -> {:ok, value} end)
      assert {:error, :unavailable} = CallSettings.capture() |> CallSettings.grant()
    end

    configure(c.previous, fn -> raise "read failed" end)
    assert {:error, :unavailable} = CallSettings.capture() |> CallSettings.grant()
  end

  test "settings read does not wait for readiness supervisor admission", c do
    configure(c.previous, fn -> {:ok, %{enabled: true, revision: 8}} end)
    supervisor = Vxpipe.CallEngine.ReadinessTaskSupervisor
    :ok = :sys.suspend(supervisor)

    try do
      reader = Task.async(fn -> CallSettings.capture() end)
      result = Task.yield(reader, 500) || Task.shutdown(reader, :brutal_kill)
      assert {:ok, %{enabled: true, revision: 8}} = result
    after
      :sys.resume(supervisor)
    end
  end

  test "room child specification captures before requesting shared supervisor startup", c do
    parent = self()

    configure(c.previous, fn ->
      send(parent, :snapshot_read)
      {:ok, %{enabled: true, revision: 9}}
    end)

    plan = struct(Vxpipe.CallEngine.ResolvedCallPlan, tenant_id: "tenant", room_id: "room")

    spec =
      Vxpipe.CallEngine.RoomIncarnationSupervisor.child_spec(plan: plan, incarnation_id: "call")

    assert_receive :snapshot_read
    assert spec.restart == :temporary
    refute_received :snapshot_read
  end

  test "untrappable loader death cannot terminate the room creator", c do
    configure(c.previous, fn -> Process.exit(self(), :kill) end)
    assert {:error, :unavailable} = CallSettings.capture() |> CallSettings.grant()
  end

  defp configure(previous, loader),
    do:
      Application.put_env(
        :vxpipe_call_engine,
        Vxpipe.CallEngine.Application,
        Keyword.put(previous, :diagnostics_settings_loader, loader)
      )

  defp identity(room), do: %{tenant_id: "tenant", room_id: room, incarnation_id: "incarnation"}
end
