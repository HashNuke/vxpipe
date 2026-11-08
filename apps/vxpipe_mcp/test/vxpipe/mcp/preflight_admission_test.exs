defmodule Vxpipe.MCP.PreflightAdmissionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.MCP.PreflightRunner

  test "a queued request cannot execute after its caller dies" do
    tasks = start_supervised!({Task.Supervisor, name: nil})

    runner =
      start_supervised!(
        {PreflightRunner, name: nil, task_supervisor: tasks, timeout: 5_000, interval: 0}
      )

    observer = self()
    :ok = :sys.suspend(runner)

    caller =
      start_supervised!(
        {Task,
         fn ->
           receive do
             :go ->
               PreflightRunner.run(runner, "queued", fn ->
                 send(observer, :callback_after_death)
                 :ok
               end)
           end
         end}
      )

    monitor = Process.monitor(caller)
    :erlang.trace(caller, true, [:send, {:tracer, observer}])

    try do
      send(caller, :go)

      assert_receive {:trace, ^caller, :send, {:"$gen_call", {^caller, _tag}, _request}, ^runner},
                     1_000

      Process.exit(caller, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^caller, :killed}
      :ok = :sys.resume(runner)
      _ = :sys.get_state(runner)
      refute_receive :callback_after_death, 100
    after
      :sys.resume(runner)
    end
  end
end
