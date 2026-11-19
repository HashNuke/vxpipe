defmodule Vxpipe.CallEngine.Diagnostics.SourceCoordinatorTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Diagnostics.{
    CaptureHandoff,
    SettingsProjection,
    SettingsSupervisor,
    SourceCoordinator,
    SourceSupervisor
  }

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.{DiagnosticRoomProbe, ResolvedCallPlan, SpeechSessionProbe}
  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.ResolvedCallPlan.{Capabilities, Participant}
  alias Vxpipe.CallEngine.RoomAuthority.{State, ParticipantTransfer.Runtime}
  alias Vxpipe.CallEngine.Room.Snapshot
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer}
  alias Vxpipe.CallEngine.Media.AudioFrame

  setup context do
    parent = self()

    settings =
      start_supervised!(
        {Agent,
         fn ->
           %{
             enabled: Map.get(context, :initially_enabled, false),
             revision: 1,
             now: System.monotonic_time(:millisecond)
           }
         end}
      )

    start_supervised!({Registry, keys: :unique, name: __MODULE__.Rooms})

    start_supervised!(
      {SettingsSupervisor,
       name: __MODULE__.Settings,
       projection: __MODULE__.Projection,
       reader: __MODULE__.Reader,
       clock: fn -> Agent.get(settings, & &1.now) end,
       send_after: fn _, _, _ -> make_ref() end,
       loader: fn ->
         send(parent, :loaded)
         {:ok, Agent.get(settings, &Map.take(&1, [:enabled, :revision]))}
       end}
    )

    assert_receive :loaded
    _ = :sys.get_state(__MODULE__.Reader)
    _ = :sys.get_state(__MODULE__.Projection)
    tree = start_supervised!({Vxpipe.CallEngine.Speech.CapabilityTree, owner: self()})

    policy = %Vxpipe.CallEngine.MediaPolicy.Snapshot{
      revision: 0,
      present_participant_ids: MapSet.new(["human", "agent"]),
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: :unrestricted,
        record_audio: true,
        save_transcripts: true
      }
    }

    capability =
      start_supervised!(
        {SpeechToText,
         owner: self(),
         tenant_id: "tenant",
         room_id: "room",
         incarnation_id: "incarnation",
         participant_id: "human",
         connection_id: "connection",
         speech_scope: Vxpipe.CallEngine.Speech.CapabilityTree.scope(tree),
         provider: {SpeechSessionProbe, [sample_rate: 16_000]},
         provider_private: [observer: self(), input_result: :ok],
         initial_policy: policy}
      )

    assert_receive {:probe_initializing, _, _}
    assert_receive {:vxpipe_stt_signal, ^capability, _, _}
    assert :ok = Enforcer.apply(capability, policy, 1_000)

    room =
      start_supervised!(
        {DiagnosticRoomProbe,
         state: room_state(capability),
         name: {:via, Registry, {__MODULE__.Rooms, {"tenant", "room"}}}}
      )

    pool =
      start_supervised!(
        {SourceSupervisor,
         name: __MODULE__.Pool,
         workers: __MODULE__.Workers,
         inference: __MODULE__.Inference,
         tasks: __MODULE__.Tasks,
         runtime: __MODULE__.Runtime,
         coordinator: __MODULE__.Coordinator,
         registry: __MODULE__.Rooms,
         projection: __MODULE__.Projection,
         maximum_sources: 1,
         poll_interval_ms: 1_000,
         collector: fn context ->
           send(parent, {:collector_started, context})

           CaptureHandoff.new(parent,
             owner: context.capability,
             projection: __MODULE__.Projection
           )
         end}
      )

    frame = %AudioFrame{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "human",
      connection_id: "connection",
      track_id: "audio",
      source_epoch: make_ref(),
      codec: :linear16,
      sample_rate: 16_000,
      channels: 1,
      sequence_number: 1,
      timestamp: 0,
      received_at: System.monotonic_time(:millisecond),
      payload: <<0, 0, 1, 0>>
    }

    %{settings: settings, capability: capability, room: room, pool: pool, frame: frame}
  end

  test "enabled scanning discovers and attaches once; disable leaves provider input unchanged",
       ctx do
    assert %{active_sources: 0, pending?: false} = SourceCoordinator.scan(__MODULE__.Coordinator)
    assert :sys.get_state(ctx.capability).diagnostic_probe == nil
    enable(ctx.settings, true, 2)
    assert %{pending?: true} = SourceCoordinator.scan(__MODULE__.Coordinator)
    assert :ok = SpeechToText.push_audio(ctx.capability, ctx.frame)
    assert_receive {:collector_started, context}, 1_000
    assert context.identity.call_id == "call"
    assert context.mode == :benchmark_only

    assert %{active_sources: 1, pending?: false} =
             SourceCoordinator.status(__MODULE__.Coordinator)

    input = :sys.get_state(ctx.capability).diagnostic_tap.handoff
    assert CaptureHandoff.current?(input)
    assert %{active_sources: 1, pending?: false} = SourceCoordinator.scan(__MODULE__.Coordinator)
    refute_received {:collector_started, _}
    monitor = Process.monitor(input.receiver)
    SettingsProjection.invalidate(__MODULE__.Projection)
    assert %{pending?: false} = SourceCoordinator.scan(__MODULE__.Coordinator)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    refute CaptureHandoff.current?(input)
    assert :ok = SpeechToText.push_audio(ctx.capability, %{ctx.frame | sequence_number: 2})
    assert_receive {:probe_input, _}
  end

  test "source retirement permits a fresh attachment with distinct run identity", ctx do
    enable(ctx.settings, true, 2)
    assert %{pending?: true} = SourceCoordinator.scan(__MODULE__.Coordinator)
    assert :ok = SpeechToText.push_audio(ctx.capability, ctx.frame)
    assert_receive {:collector_started, first}, 1_000
    assert %{active_sources: 1} = SourceCoordinator.status(__MODULE__.Coordinator)
    old = :sys.get_state(ctx.capability).diagnostic_tap.handoff
    monitor = Process.monitor(old.receiver)
    frame = %{ctx.frame | source_epoch: make_ref(), sequence_number: 2}
    assert :ok = SpeechToText.push_audio(ctx.capability, frame)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert %{pending?: true} = SourceCoordinator.scan(__MODULE__.Coordinator)
    assert :ok = SpeechToText.push_audio(ctx.capability, %{frame | sequence_number: 3})
    assert_receive {:collector_started, second}, 1_000
    assert first.run_id != second.run_id
    assert second.source_epoch == frame.source_epoch
    assert %{active_sources: 1} = SourceCoordinator.status(__MODULE__.Coordinator)
  end

  @tag initially_enabled: true
  test "automatic startup scanning attaches and coordinator failure leaves speech alive", ctx do
    coordinator = Process.whereis(__MODULE__.Coordinator)
    _ = :sys.get_state(coordinator)
    assert :sys.get_state(ctx.capability).diagnostic_probe != nil
    assert :ok = SpeechToText.push_audio(ctx.capability, ctx.frame)
    assert_receive {:collector_started, _}, 1_000
    assert %{active_sources: 1} = SourceCoordinator.status(coordinator)
    input = :sys.get_state(ctx.capability).diagnostic_tap.handoff
    worker_monitor = Process.monitor(input.receiver)
    coordinator_monitor = Process.monitor(coordinator)
    Process.exit(coordinator, :kill)
    assert_receive {:DOWN, ^coordinator_monitor, :process, ^coordinator, :killed}
    assert_receive {:DOWN, ^worker_monitor, :process, _, _}, 1_000
    _ = Supervisor.which_children(ctx.pool)
    refute CaptureHandoff.current?(input)
    assert :ok = SpeechToText.push_audio(ctx.capability, %{ctx.frame | sequence_number: 2})
    assert_receive {:probe_input, _}
    refute_received {:vxpipe_stt_signal, _, _, %{kind: :failed}}
  end

  test "retires an active attachment after selected agent becomes unavailable at full capacity",
       ctx do
    enable(ctx.settings, true, 2)
    assert %{pending?: true} = SourceCoordinator.scan(__MODULE__.Coordinator)
    assert :ok = SpeechToText.push_audio(ctx.capability, ctx.frame)
    assert_receive {:collector_started, _}, 1_000
    assert %{active_sources: 1} = SourceCoordinator.status(__MODULE__.Coordinator)
    input = :sys.get_state(ctx.capability).diagnostic_tap.handoff
    monitor = Process.monitor(input.receiver)
    :sys.replace_state(ctx.room, fn state -> %{state | text_capability: nil} end)

    assert {:error, :unsupported_call} =
             Vxpipe.CallEngine.RoomAuthority.DiagnosticSources.query(ctx.room)

    _ = SourceCoordinator.scan(__MODULE__.Coordinator)
    send(input.receiver, :check_grant)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_100
  end

  test "rejects source removed from room during collector callback", ctx do
    parent = self()

    :sys.replace_state(__MODULE__.Coordinator, fn state ->
      %{
        state
        | collector: fn context ->
            :sys.replace_state(ctx.room, fn room -> %{room | connections: %{}} end)

            {:ok, output} =
              CaptureHandoff.new(parent,
                owner: context.capability,
                projection: __MODULE__.Projection
              )

            send(parent, :collector_replaced_source)
            {:ok, output}
          end
      }
    end)

    enable(ctx.settings, true, 2)
    assert %{pending?: true} = SourceCoordinator.scan(__MODULE__.Coordinator)
    assert :ok = SpeechToText.push_audio(ctx.capability, ctx.frame)
    assert_receive :collector_replaced_source, 1_000

    assert {:ok, %{sources: []}} =
             Vxpipe.CallEngine.RoomAuthority.DiagnosticSources.query(ctx.room)

    assert %{active_sources: 0, pending?: false} =
             SourceCoordinator.status(__MODULE__.Coordinator)
  end

  test "retires an active attachment after its source leaves eligible room candidates", ctx do
    enable(ctx.settings, true, 2)
    assert %{pending?: true} = SourceCoordinator.scan(__MODULE__.Coordinator)
    assert :ok = SpeechToText.push_audio(ctx.capability, ctx.frame)
    assert_receive {:collector_started, _}, 1_000
    assert %{active_sources: 1} = SourceCoordinator.status(__MODULE__.Coordinator)
    input = :sys.get_state(ctx.capability).diagnostic_tap.handoff
    monitor = Process.monitor(input.receiver)
    :sys.replace_state(ctx.room, fn state -> %{state | connections: %{}} end)

    assert {:ok, %{sources: []}} =
             Vxpipe.CallEngine.RoomAuthority.DiagnosticSources.query(ctx.room)

    _ = SourceCoordinator.scan(__MODULE__.Coordinator)
    send(input.receiver, :check_grant)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_100
  end

  test "rejects source changed after discovery but before collector returns", ctx do
    parent = self()
    next_frame = %{ctx.frame | source_epoch: make_ref(), sequence_number: 2}

    :sys.replace_state(__MODULE__.Coordinator, fn state ->
      %{
        state
        | collector: fn context ->
            :ok = SpeechToText.push_audio(ctx.capability, next_frame)

            {:ok, output} =
              CaptureHandoff.new(parent,
                owner: context.capability,
                projection: __MODULE__.Projection
              )

            send(parent, :collector_replaced_epoch)
            {:ok, output}
          end
      }
    end)

    enable(ctx.settings, true, 2)
    assert %{pending?: true} = SourceCoordinator.scan(__MODULE__.Coordinator)
    assert :ok = SpeechToText.push_audio(ctx.capability, ctx.frame)
    assert_receive :collector_replaced_epoch, 1_000

    assert %{active_sources: 0, pending?: false} =
             SourceCoordinator.status(__MODULE__.Coordinator)
  end

  test "coordinator failure retires collector output authority independently of terminate callback",
       ctx do
    enable(ctx.settings, true, 2)
    assert %{pending?: true} = SourceCoordinator.scan(__MODULE__.Coordinator)
    assert :ok = SpeechToText.push_audio(ctx.capability, ctx.frame)
    assert_receive {:collector_started, _}, 1_000
    assert %{active_sources: 1} = SourceCoordinator.status(__MODULE__.Coordinator)
    input = :sys.get_state(ctx.capability).diagnostic_tap.handoff
    output = :sys.get_state(input.receiver).output
    assert CaptureHandoff.current?(output)
    worker_monitor = Process.monitor(input.receiver)
    coordinator = Process.whereis(__MODULE__.Coordinator)
    coordinator_monitor = Process.monitor(coordinator)
    Process.exit(coordinator, :kill)
    assert_receive {:DOWN, ^coordinator_monitor, :process, ^coordinator, :killed}
    assert_receive {:DOWN, ^worker_monitor, :process, _, _}, 1_000
    _ = Supervisor.which_children(ctx.pool)
    refute CaptureHandoff.current?(input)
    refute CaptureHandoff.current?(output)
  end

  test "collector exception does not crash coordinator or attach", ctx do
    coordinator = Process.whereis(__MODULE__.Coordinator)

    :sys.replace_state(coordinator, fn state ->
      %{state | collector: fn _ -> raise "collector broke" end}
    end)

    enable(ctx.settings, true, 2)
    assert %{pending?: true} = SourceCoordinator.scan(coordinator)
    assert :ok = SpeechToText.push_audio(ctx.capability, ctx.frame)

    assert %{active_sources: 0, pending?: false, last_reason: :collector_unavailable} =
             SourceCoordinator.status(coordinator)

    assert :sys.get_state(ctx.capability).diagnostic_tap == nil
  end

  test "grant invalidation during collector rejects attachment", ctx do
    parent = self()

    :sys.replace_state(__MODULE__.Coordinator, fn state ->
      %{
        state
        | collector: fn context ->
            {:ok, output} =
              CaptureHandoff.new(parent,
                owner: context.capability,
                projection: __MODULE__.Projection
              )

            SettingsProjection.invalidate(__MODULE__.Projection)
            _ = :sys.get_state(__MODULE__.Projection)
            send(parent, {:collector_output, output})
            {:ok, output}
          end
      }
    end)

    enable(ctx.settings, true, 2)
    assert %{pending?: true} = SourceCoordinator.scan(__MODULE__.Coordinator)
    assert :ok = SpeechToText.push_audio(ctx.capability, ctx.frame)
    assert_receive {:collector_output, output}, 1_000

    assert %{active_sources: 0, pending?: false} =
             SourceCoordinator.status(__MODULE__.Coordinator)

    refute CaptureHandoff.current?(output)
    assert :sys.get_state(ctx.capability).diagnostic_tap == nil
  end

  test "coordinator rejects source readiness received after its pending deadline", ctx do
    enable(ctx.settings, true, 2)
    assert %{pending?: true} = SourceCoordinator.scan(__MODULE__.Coordinator)
    coordinator = Process.whereis(__MODULE__.Coordinator)
    :ok = :sys.suspend(coordinator)

    try do
      assert :ok = SpeechToText.push_audio(ctx.capability, ctx.frame)
      Process.send_after(self(), :coordinator_deadline_elapsed, 550)
      assert_receive :coordinator_deadline_elapsed, 1_000
    after
      :sys.resume(coordinator)
    end

    assert %{active_sources: 0, pending?: false} = SourceCoordinator.status(coordinator)
    refute_received {:collector_started, _}
  end

  test "slow capability discovery stays within coordinator scan call budget", ctx do
    enable(ctx.settings, true, 2)
    :ok = :sys.suspend(ctx.capability)

    try do
      result =
        try do
          SourceCoordinator.scan(__MODULE__.Coordinator)
        catch
          :exit, reason -> {:scan_exit, reason}
        end

      assert %{active_sources: 0, pending?: false, last_reason: :source_unavailable} = result
    after
      :sys.resume(ctx.capability)
    end
  end

  test "unrelated candidate insertion does not retire a still-current source", ctx do
    enable(ctx.settings, true, 2)
    assert %{pending?: true} = SourceCoordinator.scan(__MODULE__.Coordinator)
    assert :ok = SpeechToText.push_audio(ctx.capability, ctx.frame)
    assert_receive {:collector_started, _}, 1_000
    assert %{active_sources: 1} = SourceCoordinator.status(__MODULE__.Coordinator)
    input = :sys.get_state(ctx.capability).diagnostic_tap.handoff

    :sys.replace_state(ctx.room, fn state ->
      original = Map.fetch!(state.connections, "connection")

      additions =
        Map.new(1..32, fn i ->
          {"before_" <> String.pad_leading(Integer.to_string(i), 3, "0"),
           %{original | speech_to_text: %{capability: self()}}}
        end)

      %{state | connections: Map.merge(state.connections, additions)}
    end)

    assert {:ok, %{sources: [_]}} =
             Vxpipe.CallEngine.RoomAuthority.DiagnosticSources.query(ctx.room, "before_032", 32)

    _ = SourceCoordinator.scan(__MODULE__.Coordinator)
    assert CaptureHandoff.current?(input)
  end

  defp enable(settings, enabled, revision) do
    Agent.update(settings, &%{&1 | enabled: enabled, revision: revision, now: &1.now + 1_000})
    SettingsProjection.invalidate(__MODULE__.Projection)
    _ = :sys.get_state(__MODULE__.Projection)
    token = :sys.get_state(__MODULE__.Projection).poll
    send(__MODULE__.Projection, {:poll, token})
    assert_receive :loaded
    _ = :sys.get_state(__MODULE__.Reader)
    _ = :sys.get_state(__MODULE__.Projection)
  end

  defp room_state(capability) do
    agent =
      struct(Participant,
        kind: :agent,
        participant_id: "agent",
        capabilities: %Capabilities{
          model_inference: struct(CapabilitySelection, kind: :model_inference)
        }
      )

    human = struct(Participant, kind: :human, participant_id: "human")

    plan =
      struct(ResolvedCallPlan,
        tenant_id: "tenant",
        room_id: "room",
        call_id: "call",
        participants: %{"agent" => agent, "human" => human}
      )

    snapshot = %Snapshot{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      lifecycle: :open,
      created_by_actor_id: "actor",
      created_by_command_id: "command"
    }

    state =
      State.new(
        %Vxpipe.CallEngine.Archive.Recorder{port: nil, participant_activations: %{}},
        snapshot,
        %{}
      )

    %{
      state
      | text_capability: %{participant_id: "agent", pid: self()},
        participant_ids: MapSet.new(["agent", "human"]),
        participant_transfer_runtime: %Runtime{plan: plan, startup_options: []},
        connections: %{
          "connection" => %{
            participant_id: "human",
            role: :human,
            admission: :main,
            speech_to_text: %{capability: capability}
          }
        }
    }
  end
end
