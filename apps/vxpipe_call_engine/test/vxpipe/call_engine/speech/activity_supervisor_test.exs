defmodule Vxpipe.CallEngine.Speech.ActivitySupervisorTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Speech.{ActivityRuntime, ActivitySupervisor, Silero}

  test "runtime failure retires inference tasks under the same ownership tree" do
    owner = self()

    start_supervised!(
      {ActivitySupervisor,
       name: __MODULE__.Supervisor,
       tasks: __MODULE__.Tasks,
       runtime: __MODULE__.Runtime,
       load: fn -> {:ok, :model} end,
       classify: fn _, _, _ ->
         send(owner, {:classifying, self()})
         receive do: (:continue -> {:ok, Silero.new(), [0.8]})
       end}
    )

    assert {:ok, _ref} = ActivityRuntime.submit(Silero.new(), <<1, 0>>, __MODULE__.Runtime)
    assert_receive {:classifying, worker}
    worker_monitor = Process.monitor(worker)
    runtime = GenServer.whereis(__MODULE__.Runtime)
    runtime_monitor = Process.monitor(runtime)
    Process.exit(runtime, :kill)
    assert_receive {:DOWN, ^runtime_monitor, :process, ^runtime, :killed}
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, _reason}, 1_000
  end

  test "the application shares only public model state, never allocation workers" do
    assert Process.whereis(ActivityRuntime) == nil
    assert Process.whereis(ActivitySupervisor) == nil
    assert {:ok, first} = Vxpipe.CallEngine.Speech.Silero.ModelCache.fetch()
    assert {:ok, second} = Vxpipe.CallEngine.Speech.Silero.ModelCache.fetch()
    assert first == second
    refute inspect(:sys.get_status(Vxpipe.CallEngine.Speech.Silero.ModelCache)) =~ "Ortex.Model"
  end

  test "one allocation's runtime failure does not retire another allocation's worker" do
    owner = self()

    for {name, tasks, runtime, id} <- [
          {__MODULE__.Left, __MODULE__.LeftTasks, __MODULE__.LeftRuntime, :left},
          {__MODULE__.Right, __MODULE__.RightTasks, __MODULE__.RightRuntime, :right}
        ] do
      start_supervised!(
        {ActivitySupervisor,
         name: name,
         tasks: tasks,
         runtime: runtime,
         load: fn -> {:ok, :model} end,
         classify: fn _, _, _ ->
           send(owner, {:classifying, id, self()})
           receive do: (:continue -> {:ok, Silero.new(), [0.8]})
         end},
        id: id
      )
    end

    assert {:ok, _left} = ActivityRuntime.submit(Silero.new(), <<1, 0>>, __MODULE__.LeftRuntime)
    assert {:ok, right} = ActivityRuntime.submit(Silero.new(), <<1, 0>>, __MODULE__.RightRuntime)
    assert_receive {:classifying, :left, left_worker}
    assert_receive {:classifying, :right, right_worker}
    monitor = Process.monitor(left_worker)
    Process.exit(GenServer.whereis(__MODULE__.LeftRuntime), :kill)
    assert_receive {:DOWN, ^monitor, :process, ^left_worker, _reason}, 1_000
    send(right_worker, :continue)
    assert_receive {:vxpipe_speech_activity, ^right, {:ok, _, [0.8]}}
  end
end
