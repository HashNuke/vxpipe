defmodule Vxpipe.CallEngine.Diagnostics.SourceWorkerTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Diagnostics.{
    AttachmentLease,
    CaptureHandoff,
    SettingsSupervisor,
    SourceWorker
  }

  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Speech.{ActivityRuntime, ActivitySupervisor}

  setup context do
    parent = self()

    start_supervised!(
      {SettingsSupervisor,
       name: __MODULE__.Settings,
       projection: __MODULE__.Projection,
       reader: __MODULE__.Reader,
       loader: fn ->
         send(parent, :settings)
         {:ok, %{enabled: true, revision: 1}}
       end}
    )

    assert_receive :settings
    _ = :sys.get_state(__MODULE__.Reader)
    _ = :sys.get_state(__MODULE__.Projection)

    start_supervised!(
      {ActivitySupervisor,
       name: __MODULE__.Pool,
       tasks: __MODULE__.Tasks,
       runtime: __MODULE__.Runtime,
       diagnostic_capacity: 1,
       load: fn -> {:ok, :model} end,
       classify: fn _, stream, pcm ->
         send(parent, {:infer, self(), pcm})
         send(parent, {:stream, self(), stream})

         receive do
           {:finish, probabilities} ->
             {:ok, %{stream | samples: stream.samples + 512 * length(probabilities)},
              probabilities}
         end
       end}
    )

    {:ok, output} =
      CaptureHandoff.new(self(), projection: __MODULE__.Projection, maximum_count: 1)

    epoch = make_ref()
    startup_clock = :atomics.new(1, signed: true)

    lease =
      if context[:startup_lease] do
        {:ok, lease} =
          AttachmentLease.reserve(AttachmentLease.gate(1), self(),
            clock: fn -> :atomics.get(startup_clock, 1) end
          )

        lease
      end

    worker =
      start_supervised!(
        {SourceWorker,
         owner: self(),
         attachment_lease: lease,
         output: output,
         projection: __MODULE__.Projection,
         admission: ActivityRuntime.diagnostic_admission(__MODULE__.Runtime),
         source_epoch: epoch,
         clock_id: "clock",
         source_id: "source",
         origin_us: -1_000_000,
         clock: fn -> 0 end,
         maximum_count: 2}
      )

    input = SourceWorker.handoff(worker)

    %{
      worker: worker,
      input: input,
      output: output,
      epoch: epoch,
      lease: lease,
      startup_clock: startup_clock
    }
  end

  @tag startup_lease: true
  test "cancelled attachment cannot return a handoff and retires its worker", ctx do
    monitor = Process.monitor(ctx.worker)
    AttachmentLease.cancel(ctx.lease)
    assert {:error, :unavailable} = SourceWorker.handoff(ctx.worker)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    refute CaptureHandoff.current?(ctx.input)
  end

  @tag startup_lease: true
  test "unadopted attachment expires without starting inference", ctx do
    monitor = Process.monitor(ctx.worker)
    :atomics.put(ctx.startup_clock, 1, 500)
    send(ctx.worker, :check_grant)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    refute CaptureHandoff.current?(ctx.input)
    refute_receive {:infer, _, _}
  end

  @tag startup_lease: true
  test "adopted attachment remains available after the startup deadline", ctx do
    assert AttachmentLease.adopt(ctx.lease)
    AttachmentLease.finish(ctx.lease)
    :atomics.put(ctx.startup_clock, 1, 500)
    send(ctx.worker, :check_grant)
    assert SourceWorker.handoff(ctx.worker) == ctx.input
    assert CaptureHandoff.current?(ctx.input)
  end

  test "sequential inference retains bounded input reservations and emits mapped boundaries",
       ctx do
    audio = frame(ctx.epoch, 0, 4 * 512, -872)
    assert :ok = CaptureHandoff.offer(ctx.input, {:audio, audio})
    assert_receive {:infer, task, _}
    assert %{pending_count: 1} = CaptureHandoff.stats(ctx.input)
    send(task, {:finish, List.duplicate(0.9, 4)})

    assert_receive {:vxpipe_diagnostic_capture, _, _,
                    {:acoustic_boundary, 0, :speech_started, 0, 0, 1_000_000, _, :partial_start},
                    _} = message

    consume(ctx.output, message)
    _ = :sys.get_state(ctx.worker)
    assert %{pending_count: 0} = CaptureHandoff.stats(ctx.input)

    silence = %{frame(ctx.epoch, 2048, 16 * 512, -360) | sequence_number: 2}
    assert :ok = CaptureHandoff.offer(ctx.input, {:audio, silence})
    assert_receive {:infer, task, _}
    send(task, {:finish, List.duplicate(0.0, 16)})

    assert_receive {:vxpipe_diagnostic_capture, _, _,
                    {:acoustic_boundary, 0, :speech_ended, 2048, 128_000, 1_000_000, _,
                     :partial_start}, _} = message

    consume(ctx.output, message)
  end

  test "revocation drops queued audio and kills only the diagnostic consumer", ctx do
    audio = frame(ctx.epoch, 0, 512, -968)
    assert :ok = CaptureHandoff.offer(ctx.input, {:audio, audio})
    assert_receive {:infer, task, _}

    assert :ok =
             CaptureHandoff.offer(
               ctx.input,
               {:audio, %{audio | timestamp: 512, sequence_number: 2}}
             )

    assert {:error, :full} = CaptureHandoff.offer(ctx.input, {:audio, audio})
    worker_monitor = Process.monitor(ctx.worker)
    task_monitor = Process.monitor(task)
    CaptureHandoff.close(ctx.input)
    send(ctx.worker, :check_grant)
    assert_receive {:DOWN, ^worker_monitor, :process, _, :normal}
    assert_receive {:DOWN, ^task_monitor, :process, _, :killed}
    assert %{pending_count: 0, open?: false} = CaptureHandoff.stats(ctx.input)
    refute_receive {:infer, _, _}

    refute_receive {:vxpipe_diagnostic_capture, _, _, {:acoustic_boundary, _, _, _, _, _, _, _},
                    _}
  end

  test "provider settlement does not reset the standalone detector", ctx do
    assert :ok = CaptureHandoff.offer(ctx.input, {:audio, frame(ctx.epoch, 0, 2048, -872)})
    assert_receive {:infer, task, _}
    send(task, {:finish, List.duplicate(0.9, 4)})

    assert_receive {:vxpipe_diagnostic_capture, _, _,
                    {:acoustic_boundary, _, :speech_started, _, _, _, _, _}, _} = message

    consume(ctx.output, message)
    assert :ok = CaptureHandoff.offer(ctx.input, {:reset, 99, :provider_turn_settled, -800_000})

    assert :ok =
             CaptureHandoff.offer(
               ctx.input,
               {:audio, %{frame(ctx.epoch, 2048, 8192, -360) | sequence_number: 2}}
             )

    assert_receive {:infer, task, _}
    send(task, {:finish, List.duplicate(0.0, 16)})

    assert_receive {:vxpipe_diagnostic_capture, _, _,
                    {:acoustic_boundary, 0, :speech_ended, 2048, _, _, _, _}, _}
  end

  test "output saturation stops observation instead of growing the collector queue", ctx do
    assert :ok = CaptureHandoff.offer(ctx.output, {:reset, 0, :partial_start, 0})
    monitor = Process.monitor(ctx.worker)
    assert :ok = CaptureHandoff.offer(ctx.input, {:audio, frame(ctx.epoch, 0, 2048, -872)})
    assert_receive {:infer, task, _}
    send(task, {:finish, List.duplicate(0.9, 4)})
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    assert %{pending_count: 1, overflow: 1} = CaptureHandoff.stats(ctx.output)

    assert {:error, :unavailable} =
             CaptureHandoff.offer(ctx.input, {:audio, frame(ctx.epoch, 0, 512, -968)})
  end

  test "duplicates do not execute another model job", ctx do
    audio = frame(ctx.epoch, 0, 2048, -872)
    assert :ok = CaptureHandoff.offer(ctx.input, {:audio, audio})
    assert_receive {:infer, task, _}
    send(task, {:finish, List.duplicate(0.9, 4)})

    assert_receive {:vxpipe_diagnostic_capture, _, _, {:acoustic_boundary, _, _, _, _, _, _, _},
                    _} = message

    consume(ctx.output, message)
    assert :ok = CaptureHandoff.offer(ctx.input, {:audio, audio})
    _ = :sys.get_state(ctx.worker)
    assert %{pending_count: 0} = CaptureHandoff.stats(ctx.input)
    refute_receive {:infer, _, _}
  end

  test "source gaps reset benchmark recurrence and report a distinct epoch", ctx do
    assert :ok = CaptureHandoff.offer(ctx.input, {:audio, frame(ctx.epoch, 0, 2048, -872)})
    assert_receive {:infer, task, _}
    send(task, {:finish, List.duplicate(0.9, 4)})

    assert_receive {:vxpipe_diagnostic_capture, _, _, {:acoustic_boundary, _, _, _, _, _, _, _},
                    _} = message

    consume(ctx.output, message)
    next = %{frame(ctx.epoch, 4096, 512, -712) | sequence_number: 3}
    assert :ok = CaptureHandoff.offer(ctx.input, {:audio, next})
    assert_receive {:vxpipe_diagnostic_capture, _, _, {:reset, 1, :audio_gap, _}, _} = message
    consume(ctx.output, message)
    assert_receive {:infer, next_task, _}
    assert_receive {:stream, ^next_task, %{samples: 0, pending: ""}}
    send(next_task, {:finish, [0.0]})

    refute_receive {:vxpipe_diagnostic_capture, _, _,
                    {:acoustic_boundary, _, :speech_ended, _, _, _, _, _}, _}
  end

  test "process status cannot expose queued PCM", ctx do
    pcm = :binary.copy("private-pcm-data!", 64)
    audio = %{frame(ctx.epoch, 0, 512, -968) | payload: pcm}
    assert :ok = CaptureHandoff.offer(ctx.input, {:audio, audio})
    assert_receive {:infer, _, _}
    assert :ok = CaptureHandoff.offer(ctx.input, {:audio, audio})
    refute inspect(:sys.get_status(ctx.worker)) =~ "private-pcm-data"
  end

  test "packaged model preserves sample correspondence across partial model windows", ctx do
    alias Vxpipe.CallEngine.Diagnostics.SourceSupervisor

    start_supervised!(
      {SourceSupervisor,
       name: __MODULE__.RealPool,
       workers: __MODULE__.RealWorkers,
       inference: __MODULE__.RealInference,
       tasks: __MODULE__.RealTasks,
       runtime: __MODULE__.RealRuntime,
       maximum_sources: 1}
    )

    {:ok, output} = CaptureHandoff.new(self(), projection: __MODULE__.Projection)

    options = [
      agent:
        struct(Vxpipe.CallEngine.ResolvedCallPlan.Participant,
          kind: :agent,
          capabilities: %Vxpipe.CallEngine.ResolvedCallPlan.Capabilities{
            model_inference:
              struct(Vxpipe.CallEngine.CallSpec.CapabilitySelection, kind: :model_inference)
          }
        ),
      owner: self(),
      output: output,
      projection: __MODULE__.Projection,
      source_epoch: ctx.epoch,
      clock_id: "clock",
      source_id: "source",
      origin_us: -1_000_000,
      clock: fn -> 3_000_000 end
    ]

    assert {:ok, worker} =
             SourceSupervisor.start_source(
               options,
               __MODULE__.RealWorkers,
               __MODULE__.RealRuntime
             )

    input = SourceWorker.handoff(worker)
    audio = File.read!(Vxpipe.Providers.Deepgram.LiveFixture.pcm_path())
    chunks = for <<chunk::binary-size(32_000) <- audio>>, do: chunk

    chunks
    |> Enum.take(3)
    |> Enum.with_index()
    |> Enum.each(fn {pcm, index} ->
      frame = %{
        frame(ctx.epoch, index * 16_000, 16_000, index * 1_000)
        | sequence_number: index + 1,
          payload: pcm
      }

      assert :ok = CaptureHandoff.offer(input, {:audio, frame})
    end)

    assert_receive {:vxpipe_diagnostic_capture, _, _,
                    {:acoustic_boundary, 0, :speech_started, 4096, 256_000, 4_000_000, _,
                     :partial_start}, _} = message,
                   20_000

    consume(output, message)

    assert_receive {:vxpipe_diagnostic_capture, _, _,
                    {:acoustic_boundary, 0, :speech_ended, 34816, 2_176_000, 4_000_000, _,
                     :partial_start}, _} = message,
                   5_000

    consume(output, message)
  end

  test "supervised shutdown releases queued and in-flight capture reservations", ctx do
    audio = frame(ctx.epoch, 0, 512, -968)
    assert :ok = CaptureHandoff.offer(ctx.input, {:audio, audio})
    assert_receive {:infer, task, _}
    assert :ok = CaptureHandoff.offer(ctx.input, {:audio, audio})
    _ = :sys.get_state(ctx.worker)
    monitor = Process.monitor(task)
    assert :ok = stop_supervised(SourceWorker)
    assert_receive {:DOWN, ^monitor, :process, _, :killed}
    assert %{pending_count: 0, open?: false} = CaptureHandoff.stats(ctx.input)
  end

  defp consume(handoff, message) do
    assert {:ok, _, charge} = CaptureHandoff.message(handoff, message)
    CaptureHandoff.release(handoff, charge, :processed)
  end

  defp frame(epoch, timestamp, samples, received) do
    %AudioFrame{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "human",
      connection_id: "connection",
      track_id: "audio",
      codec: :linear16,
      channels: 1,
      sample_rate: 16_000,
      timestamp: timestamp,
      sequence_number: 1,
      received_at: received,
      source_epoch: epoch,
      payload: :binary.copy(<<1, 0>>, samples)
    }
  end
end
