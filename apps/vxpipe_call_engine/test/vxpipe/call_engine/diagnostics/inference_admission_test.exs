defmodule Vxpipe.CallEngine.Diagnostics.InferenceAdmissionTest do
  use ExUnit.Case, async: false

  setup do
    Vxpipe.CallEngine.TestCallSettings.start!(__MODULE__)
    :ok
  end

  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff, InferenceAdmission}
  alias Vxpipe.CallEngine.Speech.{ActivityRuntime, ActivitySupervisor, Silero}

  setup do
    parent = self()

    {:ok, grant} =
      CaptureHandoff.new(self(), settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))

    start_supervised!(
      {ActivitySupervisor,
       name: __MODULE__.Pool,
       tasks: __MODULE__.Tasks,
       runtime: __MODULE__.Runtime,
       diagnostic_capacity: 1,
       load: fn ->
         send(parent, :loaded)
         {:ok, :model}
       end,
       classify: fn _, stream, audio ->
         send(parent, {:classify, self(), audio})
         send(parent, {:stream, stream})
         receive do: (:finish -> {:ok, stream, [0.8]})
       end}
    )

    %{grant: grant, admission: ActivityRuntime.diagnostic_admission(__MODULE__.Runtime)}
  end

  test "offers remain bounded while inference runtime is suspended", ctx do
    :sys.suspend(__MODULE__.Runtime)

    try do
      assert {:ok, ref} =
               InferenceAdmission.submit(ctx.admission, ctx.grant, Silero.new(), <<1, 0>>)

      assert {:error, :full} =
               InferenceAdmission.submit(ctx.admission, ctx.grant, Silero.new(), <<1, 0>>)

      assert InferenceAdmission.pending(ctx.admission) == 1
      refute_received :loaded
      send(self(), {:requested, ref})
    after
      :sys.resume(__MODULE__.Runtime)
    end

    assert_receive {:requested, ref}
    assert_receive {:classify, task, <<1, 0>>}
    assert InferenceAdmission.pending(ctx.admission) == 1
    send(task, :finish)
    assert_receive {:vxpipe_speech_activity, ^ref, {:ok, _, [0.8]}}
    assert InferenceAdmission.pending(ctx.admission) == 0
  end

  test "revoked queued audio never loads a model", ctx do
    :sys.suspend(__MODULE__.Runtime)

    try do
      assert {:ok, _} =
               InferenceAdmission.submit(ctx.admission, ctx.grant, Silero.new(), <<1, 0>>)

      CaptureHandoff.close(ctx.grant)
    after
      :sys.resume(__MODULE__.Runtime)
    end

    _ = :sys.get_state(__MODULE__.Runtime)
    assert InferenceAdmission.pending(ctx.admission) == 0
    refute_received :loaded
    refute_received {:classify, _, _}
  end

  test "revocation discards late results and releases capacity after task death", ctx do
    assert {:ok, ref} =
             InferenceAdmission.submit(ctx.admission, ctx.grant, Silero.new(), <<1, 0>>)

    assert_receive {:classify, task, _}
    monitor = Process.monitor(task)
    CaptureHandoff.close(ctx.grant)
    send(task, :finish)
    assert_receive {:DOWN, ^monitor, :process, ^task, :normal}
    _ = :sys.get_state(__MODULE__.Runtime)
    assert InferenceAdmission.pending(ctx.admission) == 0
    refute_received {:vxpipe_speech_activity, ^ref, {:ok, _, _}}
  end

  test "revocation retires a stuck diagnostic task without waiting for inference timeout", ctx do
    assert {:ok, ref} =
             InferenceAdmission.submit(ctx.admission, ctx.grant, Silero.new(), <<1, 0>>)

    assert_receive {:classify, task, _}
    monitor = Process.monitor(task)
    state = :sys.get_state(__MODULE__.Runtime)
    [{task_ref, _job}] = Map.to_list(state.jobs)
    CaptureHandoff.close(ctx.grant)
    send(__MODULE__.Runtime, {:check_grant, task_ref})
    assert_receive {:DOWN, ^monitor, :process, ^task, :killed}
    _ = :sys.get_state(__MODULE__.Runtime)
    assert InferenceAdmission.pending(ctx.admission) == 0
    refute_received {:vxpipe_speech_activity, ^ref, _}
  end

  test "result delivery alone cannot release the async reservation", ctx do
    assert {:ok, ref} =
             InferenceAdmission.submit(ctx.admission, ctx.grant, Silero.new(), <<1, 0>>)

    assert_receive {:classify, task, _}
    state = :sys.get_state(__MODULE__.Runtime)
    [{task_ref, _job}] = Map.to_list(state.jobs)
    send(__MODULE__.Runtime, {task_ref, {:ok, :model, {:ok, Silero.new(), [0.8]}}})
    _ = :sys.get_state(__MODULE__.Runtime)
    assert InferenceAdmission.pending(ctx.admission) == 1
    refute_received {:vxpipe_speech_activity, ^ref, _}
    send(task, :finish)
    assert_receive {:vxpipe_speech_activity, ^ref, {:ok, _, [0.8]}}
    assert InferenceAdmission.pending(ctx.admission) == 0
  end

  test "audio backed by a large allocation is detached before queuing", ctx do
    backing = :binary.copy(<<1, 0>>, 1_000_000)
    audio = binary_part(backing, 0, 640)
    assert :binary.referenced_byte_size(audio) > 640
    assert {:ok, _} = InferenceAdmission.submit(ctx.admission, ctx.grant, Silero.new(), audio)
    assert_receive {:classify, task, copied}
    assert :binary.referenced_byte_size(copied) == 640
    send(task, :finish)
  end

  test "small tensor views cannot retain oversized backing binaries", ctx do
    tensor = Nx.broadcast(Nx.tensor(0, type: :f32), {1, 64})
    backing = :binary.copy(<<0>>, 2_000_000)
    view = binary_part(backing, 0, 256)
    tensor = %{tensor | data: %{tensor.data | state: view}}
    assert :binary.referenced_byte_size(Nx.to_binary(tensor)) > 256
    stream = %{Silero.new() | context: tensor}
    assert {:ok, _} = InferenceAdmission.submit(ctx.admission, ctx.grant, stream, <<1, 0>>)
    assert_receive {:classify, task, _}
    assert_receive {:stream, copied}
    assert :binary.referenced_byte_size(Nx.to_binary(copied.context)) == 256
    send(task, :finish)
  end

  test "packaged model recurrent state survives subsequent async offers", ctx do
    start_supervised!(
      {ActivitySupervisor,
       name: __MODULE__.RealPool,
       tasks: __MODULE__.RealTasks,
       runtime: __MODULE__.RealRuntime,
       diagnostic_capacity: 1},
      id: __MODULE__.RealPool
    )

    admission = ActivityRuntime.diagnostic_admission(__MODULE__.RealRuntime)
    audio = :binary.copy(<<0>>, 1_024)
    assert {:ok, first} = InferenceAdmission.submit(admission, ctx.grant, Silero.new(), audio)
    assert_receive {:vxpipe_speech_activity, ^first, {:ok, stream, [_]}}, 20_000
    assert stream.samples == 512
    assert {:ok, second} = InferenceAdmission.submit(admission, ctx.grant, stream, audio)
    assert_receive {:vxpipe_speech_activity, ^second, {:ok, stream, [_]}}, 5_000
    assert stream.samples == 1_024
  end

  test "invalid stream state is rejected before reserving capacity", ctx do
    for stream <- [
          %{Silero.new() | pending: :invalid},
          %{Silero.new() | context: <<1>>},
          %{Silero.new() | samples: -1}
        ] do
      assert {:error, :invalid_audio} =
               InferenceAdmission.submit(ctx.admission, ctx.grant, stream, <<1, 0>>)

      assert InferenceAdmission.pending(ctx.admission) == 0
    end
  end

  test "inference deadline reports the caller reference and retires its reservation", ctx do
    assert {:ok, ref} =
             InferenceAdmission.submit(ctx.admission, ctx.grant, Silero.new(), <<1, 0>>)

    assert_receive {:classify, task, _}
    monitor = Process.monitor(task)

    [{task_ref, _job}] =
      __MODULE__.Runtime |> :sys.get_state() |> Map.fetch!(:jobs) |> Map.to_list()

    send(__MODULE__.Runtime, {:deadline, task_ref})
    assert_receive {:vxpipe_speech_activity, ^ref, {:error, :classification_timeout}}
    assert_receive {:DOWN, ^monitor, :process, ^task, :killed}
    _ = :sys.get_state(__MODULE__.Runtime)
    assert InferenceAdmission.pending(ctx.admission) == 0
  end
end
