defmodule Vxpipe.CallEngine.Speech.ActivityRuntimeTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Speech.{ActivityRuntime, Silero}

  test "model loading is lazy and concurrent admission is bounded" do
    owner = self()

    runtime =
      runtime(
        load: fn ->
          send(owner, {:loading, self()})
          receive do: (:continue -> {:ok, :model})
        end
      )

    refute_receive {:loading, _}
    assert {:ok, ref} = ActivityRuntime.submit(Silero.new(), <<1, 0>>, runtime)
    assert_receive {:loading, worker}
    assert {:error, :busy} = ActivityRuntime.submit(Silero.new(), <<1, 0>>, runtime)
    send(worker, :continue)
    assert_receive {:vxpipe_speech_activity, ^ref, {:ok, %Silero{}, [0.8]}}
    assert {:ok, next} = ActivityRuntime.submit(Silero.new(), <<1, 0>>, runtime)
    assert_receive {:vxpipe_speech_activity, ^next, {:ok, %Silero{}, [0.8]}}
    refute_receive {:loading, _}
  end

  test "cancellation retires owned work before releasing admission" do
    owner = self()

    runtime =
      runtime(
        classify: fn _, _, _ ->
          send(owner, {:classifying, self()})
          receive do: (:continue -> {:ok, Silero.new(), [0.8]})
        end
      )

    assert {:ok, ref} = ActivityRuntime.submit(Silero.new(), <<1, 0>>, runtime)
    assert_receive {:classifying, worker}
    monitor = Process.monitor(worker)
    assert :ok = ActivityRuntime.cancel(ref, runtime)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}
    assert_receive {:vxpipe_speech_activity, ^ref, {:error, :cancelled}}
    assert {:ok, next} = ActivityRuntime.submit(Silero.new(), <<1, 0>>, runtime)
    assert_receive {:classifying, next_worker}
    send(next_worker, :continue)
    assert_receive {:vxpipe_speech_activity, ^next, {:ok, _, [0.8]}}
    refute_receive {:vxpipe_speech_activity, ^ref, {:ok, _, _}}
  end

  test "a result does not release admission before its worker terminates" do
    owner = self()

    runtime =
      runtime(
        classify: fn _, stream, _ ->
          send(owner, {:classifying, self()})
          receive do: (:continue -> {:ok, stream, [0.8]})
        end
      )

    assert {:ok, ref} = ActivityRuntime.submit(Silero.new(), <<1, 0>>, runtime)
    assert_receive {:classifying, worker}
    # Model the gap between Task result delivery and the task's monitor signal.
    send(runtime, {ref, {:ok, :model, {:ok, Silero.new(), [0.8]}}})
    _ = :sys.get_state(runtime)
    refute_received {:vxpipe_speech_activity, ^ref, _outcome}
    assert {:error, :busy} = ActivityRuntime.submit(Silero.new(), <<1, 0>>, runtime)
    monitor = Process.monitor(worker)
    send(worker, :continue)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}
    assert_receive {:vxpipe_speech_activity, ^ref, {:ok, _, [0.8]}}
  end

  test "deadlines fail accepted work safely and private status hides PCM" do
    owner = self()

    runtime =
      runtime(
        load_timeout_ms: 500,
        classify: fn _, _, _ ->
          send(owner, {:classifying, self()})
          receive do: (:continue -> {:ok, Silero.new(), [0.8]})
        end
      )

    assert {:ok, ref} = ActivityRuntime.submit(Silero.new(), "private-pcm-data", runtime)
    assert_receive {:classifying, worker}
    monitor = Process.monitor(worker)
    refute inspect(:sys.get_status(runtime)) =~ "private-pcm-data"
    assert_receive {:vxpipe_speech_activity, ^ref, {:error, :classification_timeout}}, 2_000
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}
    refute_receive {:vxpipe_speech_activity, ^ref, {:ok, _, _}}
  end

  test "loader failures expose fixed reasons and allow later admission" do
    runtime = runtime(load: fn -> raise "private-native-error" end)
    assert {:error, :invalid_audio} = ActivityRuntime.submit(Silero.new(), <<1>>, runtime)
    assert {:ok, ref} = ActivityRuntime.submit(Silero.new(), <<1, 0>>, runtime)
    assert_receive {:vxpipe_speech_activity, ^ref, {:error, :classification_failed}}
    assert {:ok, next} = ActivityRuntime.submit(Silero.new(), <<1, 0>>, runtime)
    assert_receive {:vxpipe_speech_activity, ^next, {:error, :classification_failed}}
  end

  test "inference exceptions never publish native error details" do
    runtime = runtime(classify: fn _, _, _ -> raise "private-native-error" end)
    assert {:ok, ref} = ActivityRuntime.submit(Silero.new(), <<1, 0>>, runtime)
    assert_receive {:vxpipe_speech_activity, ^ref, {:error, :classification_failed}}
  end

  test "allocation owner loss retires its inference work" do
    owner = self()

    runtime =
      runtime(
        classify: fn _, _, _ ->
          send(owner, {:classifying, self()})
          receive do: (:continue -> {:ok, Silero.new(), [0.8]})
        end
      )

    caller =
      Task.Supervisor.start_child(__MODULE__.Tasks, fn ->
        assert {:ok, ref} = ActivityRuntime.submit(Silero.new(), <<1, 0>>, runtime)
        send(owner, {:submitted, ref})
        receive do: (:stop -> :ok)
      end)

    assert {:ok, caller} = caller
    assert_receive {:submitted, ref}
    assert_receive {:classifying, worker}
    monitor = Process.monitor(worker)
    send(caller, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}
    refute_receive {:vxpipe_speech_activity, ^ref, _}
  end

  test "another allocation cannot cancel an admitted job" do
    owner = self()

    runtime =
      runtime(
        classify: fn _, _, _ ->
          send(owner, {:classifying, self()})
          receive do: (:continue -> {:ok, Silero.new(), [0.8]})
        end
      )

    assert {:ok, ref} = ActivityRuntime.submit(Silero.new(), <<1, 0>>, runtime)
    assert_receive {:classifying, worker}

    assert {:ok, _caller} =
             Task.Supervisor.start_child(__MODULE__.Tasks, fn ->
               send(owner, {:foreign_cancel, ActivityRuntime.cancel(ref, runtime)})
             end)

    assert_receive {:foreign_cancel, {:error, :unknown_job}}
    send(worker, :continue)
    assert_receive {:vxpipe_speech_activity, ^ref, {:ok, _, [0.8]}}
  end

  defp runtime(options) do
    tasks = start_supervised!({Task.Supervisor, name: __MODULE__.Tasks})

    start_supervised!(
      {ActivityRuntime,
       Keyword.merge(
         [
           name: __MODULE__.Runtime,
           task_supervisor: tasks,
           max_jobs: 1,
           load: fn -> {:ok, :model} end,
           classify: fn :model, state, _audio -> {:ok, state, [0.8]} end
         ],
         options
       )}
    )
  end
end
