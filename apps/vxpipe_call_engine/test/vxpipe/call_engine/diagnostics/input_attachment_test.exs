defmodule Vxpipe.CallEngine.Diagnostics.InputAttachmentTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Diagnostics.{
    AttachmentLease,
    CaptureHandoff,
    SettingsProjection,
    SettingsSupervisor,
    SourceAdmission,
    SourceAttachment,
    SourceWorker,
    SourceSupervisor
  }

  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.{DiagnosticRoomProbe, ResolvedCallPlan}
  alias Vxpipe.CallEngine.TestElevenLabsScribeTransport, as: Wire
  alias Vxpipe.Providers.ElevenLabs.{Scribe, STTSession}
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
             enabled: true,
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

    {:ok, config} = Scribe.new(api_key: "synthetic", commit_strategy: :vad)

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
         provider: {STTSession, [commit_strategy: :vad]},
         provider_private: [config: config, wire_module: Wire, wire_options: [observer: self()]],
         initial_policy: policy}
      )

    assert_receive {:scribe_started, wire}

    Wire.deliver_frame(
      wire,
      JSON.encode!(%{
        "message_type" => "session_started",
        "session_id" => "synthetic",
        "config" => Map.get(context, :echoes, echoed_settings())
      })
    )

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
         registry: __MODULE__.Rooms,
         projection: __MODULE__.Projection,
         attachment_gate: AttachmentLease.gate(1),
         maximum_sources: 1,
         poll_interval_ms: 1_000}
      )

    start_supervised!(
      {SourceAdmission, name: __MODULE__.Admission, gate: AttachmentLease.gate(1)}
    )

    start_supervised!({DynamicSupervisor, name: __MODULE__.RoomWorkers, strategy: :one_for_one},
      id: :room_workers
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

  test "participant attachment needs no selected agent and keeps its slot until worker exits",
       ctx do
    :sys.replace_state(ctx.room, &%{&1 | text_capability: nil})
    {candidate, packet, options} = prepare(ctx)
    assert {:ok, entry} = SourceAttachment.start_input(candidate, packet, options)
    assert :ok = SourceAdmission.adopt(__MODULE__.Admission, options.attachment_lease)
    assert SourceAttachment.current?(entry)
    assert entry.context.participant_id == "human"
    refute Map.has_key?(entry.context, :agent_id)
    assert [{_, worker, _, _}] = DynamicSupervisor.which_children(__MODULE__.RoomWorkers)
    assert worker == entry.worker
    assert DynamicSupervisor.which_children(__MODULE__.Workers) == []
    assert {:error, :capacity_unavailable} = SourceAdmission.reserve(__MODULE__.Admission, self())

    :sys.replace_state(
      ctx.room,
      &%{&1 | text_capability: %{participant_id: "different", pid: self()}}
    )

    assert SourceAttachment.current?(entry)
    monitor = Process.monitor(worker)
    SourceAttachment.close(entry)
    send(worker, :check_grant)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
    assert %{occupied_slots: 0} = SourceAdmission.status(__MODULE__.Admission)
    assert :ok = SpeechToText.push_audio(ctx.capability, %{ctx.frame | sequence_number: 2})
    assert_receive {:scribe_audio, _, _}
  end

  test "an STT source remains eligible in a mixed speech-to-speech room", ctx do
    :sys.replace_state(
      ctx.room,
      &%{
        &1
        | text_capability: nil,
          speech_to_speech_capability: %{participant_id: "agent", pid: self()}
      }
    )

    {candidate, packet, options} = prepare(ctx)
    assert {:ok, entry} = SourceAttachment.start_input(candidate, packet, options)
    assert :ok = SourceAdmission.adopt(__MODULE__.Admission, options.attachment_lease)
    assert SourceAttachment.current?(entry)
    SourceAttachment.close(entry)
  end

  test "reuse takes shared source capacity without touching the inference runtime", ctx do
    {:ok, lease} = SourceAdmission.reserve(__MODULE__.Admission, self())

    {:ok, output} =
      CaptureHandoff.new(self(), owner: ctx.capability, projection: __MODULE__.Projection)

    options = [
      owner: ctx.capability,
      coordinator: self(),
      output: output,
      projection: __MODULE__.Projection,
      attachment_lease: lease,
      mode: :operational_reuse,
      source_epoch: ctx.frame.source_epoch,
      clock_id: "clock",
      source_id: "source",
      origin_us: System.monotonic_time(:microsecond)
    ]

    assert {:ok, worker} =
             SourceSupervisor.start_input_source(
               options,
               __MODULE__.RoomWorkers,
               __MODULE__.AbsentRuntime,
               __MODULE__.Admission
             )

    assert :ok = SourceAdmission.adopt(__MODULE__.Admission, lease)
    assert %CaptureHandoff{} = SourceWorker.handoff(worker)
    assert {:error, :capacity_unavailable} = SourceAdmission.reserve(__MODULE__.Admission, self())
    monitor = Process.monitor(worker)
    assert :ok = DynamicSupervisor.terminate_child(__MODULE__.RoomWorkers, worker)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :shutdown}
    assert %{occupied_slots: 0} = SourceAdmission.status(__MODULE__.Admission)
  end

  test "missing admission tracker fails closed before creating a reuse worker", ctx do
    {:ok, lease} = SourceAdmission.reserve(__MODULE__.Admission, self())

    {:ok, output} =
      CaptureHandoff.new(self(), owner: ctx.capability, projection: __MODULE__.Projection)

    options = [
      owner: ctx.capability,
      coordinator: self(),
      output: output,
      projection: __MODULE__.Projection,
      attachment_lease: lease,
      mode: :operational_reuse,
      source_epoch: ctx.frame.source_epoch,
      clock_id: "clock",
      source_id: "source",
      origin_us: System.monotonic_time(:microsecond)
    ]

    assert {:error, :unavailable} =
             SourceSupervisor.start_input_source(
               options,
               __MODULE__.RoomWorkers,
               __MODULE__.AbsentRuntime,
               __MODULE__.AbsentAdmission
             )

    assert DynamicSupervisor.which_children(__MODULE__.RoomWorkers) == []
    SourceAdmission.cancel(__MODULE__.Admission, lease)
  end

  test "input attachment reports unavailable admission distinctly from capacity exhaustion",
       ctx do
    {candidate, packet, options} = prepare(ctx)

    assert {:error, :unavailable} =
             SourceAttachment.start_input(candidate, packet, %{
               options
               | source_admission: __MODULE__.AbsentAdmission
             })

    assert DynamicSupervisor.which_children(__MODULE__.RoomWorkers) == []
    SourceAdmission.cancel(__MODULE__.Admission, options.attachment_lease)
  end

  test "removed accepted source is rejected before collector allocation", ctx do
    {candidate, packet, options} = prepare(ctx)
    :sys.replace_state(ctx.room, &%{&1 | connections: %{}})
    assert {:error, :stale_source} = SourceAttachment.start_input(candidate, packet, options)
    refute_received {:collector_started, _}
    SourceAdmission.cancel(__MODULE__.Admission, options.attachment_lease)
    assert %{occupied_slots: 0} = SourceAdmission.status(__MODULE__.Admission)
  end

  test "source replacement during collector allocation cannot bind the observer", ctx do
    {candidate, packet, options} = prepare(ctx)
    original = options.collector

    options = %{
      options
      | collector: fn context ->
          :sys.replace_state(ctx.room, &%{&1 | connections: %{}})
          original.(context)
        end
    }

    assert {:error, :stale_source} = SourceAttachment.start_input(candidate, packet, options)
    assert DynamicSupervisor.which_children(__MODULE__.RoomWorkers) == []
    SourceAdmission.cancel(__MODULE__.Admission, options.attachment_lease)
  end

  test "invalidated collection authority cannot allocate an input observer", ctx do
    {candidate, packet, options} = prepare(ctx)
    SettingsProjection.invalidate(__MODULE__.Projection)
    assert {:error, :stale_source} = SourceAttachment.start_input(candidate, packet, options)
    refute_received {:collector_started, _}
    assert DynamicSupervisor.which_children(__MODULE__.RoomWorkers) == []
    SourceAdmission.cancel(__MODULE__.Admission, options.attachment_lease)
  end

  test "cancelled input collector allocation retains its unresolved admission charge", ctx do
    {candidate, packet, options} = prepare(ctx)
    parent = self()
    original = options.collector

    options = %{
      options
      | collector: fn context ->
          send(parent, {:blocked_collector, self()})

          receive do
            :release_collector -> original.(context)
          end
        end
    }

    helper =
      start_supervised!(%{
        id: :attachment_helper,
        start:
          {Task, :start_link,
           [
             fn ->
               send(
                 parent,
                 {:input_attachment_result,
                  SourceAttachment.start_input(candidate, packet, options)}
               )
             end
           ]},
        restart: :temporary
      })

    assert_receive {:blocked_collector, ^helper}, 1_000
    monitor = Process.monitor(helper)

    try do
      :ok = SourceAdmission.cancel(__MODULE__.Admission, options.attachment_lease)

      assert {:error, :capacity_unavailable} =
               SourceAdmission.reserve(__MODULE__.Admission, self())
    after
      send(helper, :release_collector)
      assert_receive {:DOWN, ^monitor, :process, ^helper, :normal}, 1_000
    end

    assert_receive {:input_attachment_result, {:error, :unavailable}}
    assert %{occupied_slots: 0} = SourceAdmission.status(__MODULE__.Admission)
    assert DynamicSupervisor.which_children(__MODULE__.RoomWorkers) == []
  end

  defp prepare(ctx) do
    {:ok, page} = Vxpipe.CallEngine.RoomAuthority.DiagnosticInputs.query(ctx.room)
    [source] = page.sources

    {:ok, handoff} =
      CaptureHandoff.new(self(),
        owner: ctx.capability,
        projection: __MODULE__.Projection,
        maximum_count: 2,
        maximum_bytes: 4_096
      )

    assert :ok = SpeechToText.discover_input_diagnostics(ctx.capability, handoff, 250)
    assert :ok = SpeechToText.request_diagnostic_profile(ctx.capability, handoff, 250)
    assert :ok = SpeechToText.push_audio(ctx.capability, ctx.frame)

    assert_receive {:vxpipe_diagnostic_capture, _, _, {:source_ready, _, _, _, _, _, _, _, _}, _} =
                     message

    {:ok, packet, charge} = CaptureHandoff.message(handoff, message)
    CaptureHandoff.release(handoff, charge, :processed)
    assert_receive {:vxpipe_diagnostic_capture, _, _, {:provider_profile, _, _, _}, _} = message

    {:ok, {:provider_profile, _, provider, profile}, charge} =
      CaptureHandoff.message(handoff, message)

    CaptureHandoff.release(handoff, charge, :processed)

    candidate = %{
      room: ctx.room,
      identity: page.identity,
      source: source,
      grant: handoff.grant,
      discovery_token: handoff.token,
      provider_generation: provider,
      provider_profile: profile
    }

    CaptureHandoff.close(handoff)
    {:ok, lease} = SourceAdmission.reserve(__MODULE__.Admission, self())
    parent = self()

    options = %{
      projection: __MODULE__.Projection,
      coordinator: self(),
      attachment_lease: lease,
      source_admission: __MODULE__.Admission,
      workers: __MODULE__.RoomWorkers,
      runtime: __MODULE__.Runtime,
      collector: fn context ->
        send(parent, {:collector_started, context})
        CaptureHandoff.new(parent, owner: context.capability, projection: __MODULE__.Projection)
      end
    }

    {candidate, packet, options}
  end

  defp echoed_settings do
    %{
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
