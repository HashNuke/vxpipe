defmodule Vxpipe.Calls.Diagnostics.AttachmentTest do
  use ExUnit.Case, async: false

  setup do
    Vxpipe.CallEngine.TestCallSettings.start!(__MODULE__)
    :ok
  end

  alias Vxpipe.CallEngine.Diagnostics.{
    AttachmentLease,
    CaptureHandoff,
    CallSettings
  }

  alias Vxpipe.Calls.Diagnostics.{Attachment, Collector, Supervisor}
  @now ~U[2026-11-19 12:00:00.000000Z]

  setup do
    start_supervised!(
      {Supervisor,
       name: __MODULE__.Root,
       writer_supervisor: __MODULE__.Writers,
       collector_supervisor: __MODULE__.Collectors,
       task_supervisor: __MODULE__.Tasks,
       maximum_collectors: 1}
    )

    {:ok, lease} = AttachmentLease.reserve(AttachmentLease.gate(1), self())

    context = %{
      attachment_lease: lease,
      identity: %{
        tenant_id: "tenant",
        call_id: "call",
        room_id: "room",
        incarnation_id: "incarnation"
      },
      participant_id: "human",
      connection_id: "connection",
      capability: self(),
      coordinator: self(),
      generation: make_ref(),
      provider_generation: make_ref(),
      settings_revision: 1,
      settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__),
      source_epoch: make_ref(),
      source_id: "source",
      clock_id: "clock",
      run_id: "run",
      origin_us: -10_000,
      anchor_utc: @now,
      mode: :benchmark_only,
      provider_profile: %{
        missing: [],
        acknowledged: %{
          "model_id" => "scribe_v2_realtime",
          "sample_rate" => 16_000,
          "audio_format" => "pcm_16000",
          "commit_strategy" => "vad",
          "vad_silence_threshold_secs" => 1.5,
          "vad_threshold" => 0.4,
          "min_speech_duration_ms" => 100,
          "min_silence_duration_ms" => 100,
          "keepalive_interval_ms" => 500
        }
      }
    }

    options = [
      settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__),
      collector_supervisor: __MODULE__.Collectors,
      writer_supervisor: __MODULE__.Writers,
      task_supervisor: __MODULE__.Tasks,
      repository: {Vxpipe.Calls.TestControlledLatencyRepository, self()},
      utc_now: fn -> @now end
    ]

    %{context: context, options: options}
  end

  test "admitted source starts an immutable run and returns its capture handoff without waiting for storage",
       c do
    assert {:ok, output} = Attachment.start(c.context, c.options)
    assert CaptureHandoff.current?(output)
    assert output.owner == self()
    assert_receive {:diagnostic_write, task, run}
    assert run.id == c.context.run_id
    assert run.tenant_key == "tenant"
    assert run.source_epoch == c.context.source_id
    assert run.anchor_utc == @now
    assert run.profile.provider_acknowledgement.vad_threshold == 0.4
    assert run.profile.onset_threshold == 0.5
    assert run.profile.inference_source == :benchmark_only
    send(task, {:finish, {:ok, run}})
    assert :ok = Collector.close(output.receiver, :call_ended)
    assert_receive {:diagnostic_write, task, closed}
    assert closed.state == :closed
    send(task, {:finish, {:ok, closed}})
  end

  test "omitted strategy is preserved while configured VAD mode admits capture", c do
    fields = Map.delete(c.context.provider_profile.acknowledged, "commit_strategy")

    context = %{
      c.context
      | provider_profile: %{acknowledged: fields, missing: ["commit_strategy"]}
    }

    assert {:ok, output} = Attachment.start(context, c.options)
    assert CaptureHandoff.current?(output)
    assert_receive {:diagnostic_write, task, run}
    assert run.profile.commit_strategy == :vad
    assert map_size(run.profile.provider_acknowledgement) == 8
    refute Map.has_key?(run.profile.provider_acknowledgement, :commit_strategy)
    send(task, {:finish, {:ok, run}})
  end

  test "conflicting strategy and any other absent acknowledgement field reject capture", c do
    fields = c.context.provider_profile.acknowledged

    invalid =
      [%{acknowledged: Map.put(fields, "commit_strategy", "manual"), missing: []}] ++
        for key <- Map.keys(fields), key != "commit_strategy" do
          %{acknowledged: Map.delete(fields, key), missing: [key]}
        end

    for profile <- invalid do
      assert {:error, :unavailable} =
               Attachment.start(%{c.context | provider_profile: profile}, c.options)
    end

    assert DynamicSupervisor.which_children(__MODULE__.Collectors) == []
    refute_received {:diagnostic_write, _, _}
  end

  test "cancellation while obtaining the writer handoff prevents initial persistence", c do
    parent = self()
    tasks = start_supervised!({Task.Supervisor, []})
    {:ok, lease} = AttachmentLease.reserve(AttachmentLease.gate(1), self())

    shim =
      start_supervised!(
        {Task,
         fn ->
           receive do
             {:"$gen_call", {collector, _} = from, {:start_child, child}} ->
               {:ok, writer} =
                 result = GenServer.call(__MODULE__.Writers, {:start_child, child}, :infinity)

               :ok = :sys.suspend(writer)
               :erlang.trace(collector, true, [:send, {:tracer, parent}])
               send(parent, {:writer_admitted, collector, writer})
               GenServer.reply(from, result)

               receive do
                 :done -> :ok
               end
           end
         end}
      )

    task =
      Task.Supervisor.async_nolink(tasks, fn ->
        Attachment.start(
          Map.put(c.context, :attachment_lease, lease),
          Keyword.put(c.options, :writer_supervisor, shim)
        )
      end)

    assert_receive {:writer_admitted, collector, writer}
    assert_receive {:trace, ^collector, :send, {:"$gen_call", _, :handoff}, ^writer}
    AttachmentLease.cancel(lease)
    :ok = :sys.resume(writer)
    assert {:error, :unavailable} = Task.await(task)
    refute_receive {:diagnostic_write, _, _}, 100
  end

  test "missing startup lease rejects before allocating a collector", c do
    assert {:error, :unavailable} =
             Attachment.start(Map.delete(c.context, :attachment_lease), c.options)

    assert DynamicSupervisor.which_children(__MODULE__.Collectors) == []
    refute_received {:diagnostic_write, _, _}
  end

  test "cancelled attachment lease cannot allocate a collector", c do
    {:ok, lease} = AttachmentLease.reserve(AttachmentLease.gate(1), self())
    AttachmentLease.cancel(lease)

    assert {:error, :unavailable} =
             Attachment.start(Map.put(c.context, :attachment_lease, lease), c.options)

    assert DynamicSupervisor.which_children(__MODULE__.Collectors) == []
    refute_received {:diagnostic_write, _, _}
  end

  test "unknown acknowledgement cannot allocate a collector", c do
    context = %{c.context | provider_profile: %{acknowledged: %{}, missing: ["model_id"]}}
    assert {:error, :unavailable} = Attachment.start(context, c.options)
    assert DynamicSupervisor.which_children(__MODULE__.Collectors) == []
    refute_received {:diagnostic_write, _, _}
  end

  test "disabled call snapshots and stale revisions cannot start persistence", c do
    assert {:error, :unavailable} =
             Attachment.start(%{c.context | settings_revision: 2}, c.options)

    disabled = CallSettings.new(%{enabled: false, revision: 1})
    assert {:error, :unavailable} = Attachment.start(%{c.context | settings: disabled}, c.options)
    assert DynamicSupervisor.which_children(__MODULE__.Collectors) == []
    refute_received {:diagnostic_write, _, _}
  end
end
