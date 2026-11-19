defmodule Vxpipe.CallEngine.Diagnostics.RoomServiceTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Diagnostics.{
    AttachmentLease,
    CaptureHandoff,
    SettingsProjection,
    SettingsSupervisor,
    SourceAdmission,
    RoomService,
    RoomSupervisor,
    SourcePort,
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
             enabled: Map.get(context, :collection, true),
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

    {provider, private} = provider_options(context, config, parent)

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
         provider: provider,
         provider_private: private,
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
         state: %{room_state(capability) | text_capability: nil},
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
         load: fn -> {:ok, :fixture_model} end,
         classify: classifier(parent, :benchmark),
         poll_interval_ms: 1_000}
      )

    start_supervised!(
      {SourceAdmission, name: __MODULE__.Admission, gate: AttachmentLease.gate(1)}
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

    %{
      settings: settings,
      capability: capability,
      room: room,
      pool: pool,
      frame: frame,
      wire: wire
    }
  end

  test "room service attaches its accepted input without a selected agent", ctx do
    start_port()
    start_room(ctx)
    attach(ctx)
    assert [{_, worker, _, _}] = DynamicSupervisor.which_children(__MODULE__.RoomWorkers)
    assert worker == :sys.get_state(ctx.capability).diagnostic_tap.handoff.receiver
    assert DynamicSupervisor.which_children(__MODULE__.Workers) == []
  end

  test "agent-only changes preserve the attachment and run", ctx do
    start_port()
    start_room(ctx)
    attach(ctx)
    input = :sys.get_state(ctx.capability).diagnostic_tap.handoff

    :sys.replace_state(
      ctx.room,
      &%{&1 | text_capability: %{participant_id: "specialist", pid: self()}}
    )

    assert %{active_sources: 1} = RoomService.scan(__MODULE__.Service)
    assert CaptureHandoff.current?(input)
    refute_received {:collector_started, _}
  end

  test "missing source port stays unavailable and later reconciliation can attach", ctx do
    start_room(ctx)

    assert %{active_sources: 0, pending?: false, last_reason: :unavailable} =
             RoomService.scan(__MODULE__.Service)

    assert :sys.get_state(ctx.capability).diagnostic_probe == nil
    start_port()
    RoomService.notify(__MODULE__.Service)
    attach(ctx)
  end

  test "room teardown stops attached workers and releases tracked capacity", ctx do
    start_port()
    start_room(ctx)
    attach(ctx)
    [{_, worker, _, _}] = DynamicSupervisor.which_children(__MODULE__.RoomWorkers)
    monitor = Process.monitor(worker)
    assert :ok = stop_supervised({RoomSupervisor, __MODULE__.RoomDiagnostics})
    assert_receive {:DOWN, ^monitor, :process, ^worker, reason}
    assert reason in [:normal, :shutdown]
    assert %{occupied_slots: 0} = SourceAdmission.status(__MODULE__.Admission)
    assert :ok = SpeechToText.push_audio(ctx.capability, %{ctx.frame | sequence_number: 2})
    assert_receive {:scribe_audio, _, _}
  end

  test "removed input is retired without waiting for another source", ctx do
    start_port()
    start_room(ctx)
    attach(ctx)
    input = :sys.get_state(ctx.capability).diagnostic_tap.handoff
    monitor = Process.monitor(input.receiver)
    :sys.replace_state(ctx.room, &%{&1 | connections: %{}})
    RoomService.notify(__MODULE__.Service)
    _ = RoomService.scan(__MODULE__.Service)
    send(input.receiver, :check_grant)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    refute CaptureHandoff.current?(input)
  end

  test "stalled collector stays outside service callbacks and is owned by the room", ctx do
    parent = self()

    start_port(fn _ ->
      Process.flag(:trap_exit, true)
      send(parent, {:collector_waiting, self()})

      receive do
        :release -> {:error, :unavailable}
      end
    end)

    supervisor = start_room(ctx)
    assert %{pending?: true} = RoomService.scan(__MODULE__.Service)
    assert :ok = SpeechToText.push_audio(ctx.capability, ctx.frame)
    assert_receive {:collector_waiting, helper}, 1_000
    assert %{active_sources: 0, pending?: true} = RoomService.status(__MODULE__.Service)
    monitor = Process.monitor(helper)
    assert :ok = Supervisor.stop(supervisor, :shutdown, 1_000)
    assert_receive {:DOWN, ^monitor, :process, ^helper, _}, 1_000
    assert :ok = SpeechToText.push_audio(ctx.capability, %{ctx.frame | sequence_number: 2})
  end

  test "port loss revokes observation and leaves speech running", ctx do
    port = start_port()
    start_room(ctx)
    attach(ctx)
    input = :sys.get_state(ctx.capability).diagnostic_tap.handoff
    monitor = Process.monitor(input.receiver)
    port_monitor = Process.monitor(port)
    assert :ok = stop_supervised(SourcePort)
    assert_receive {:DOWN, ^port_monitor, :process, ^port, :shutdown}
    _ = RoomService.scan(__MODULE__.Service)
    send(input.receiver, :check_grant)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    refute CaptureHandoff.current?(input)
    assert %{last_reason: :unavailable} = RoomService.scan(__MODULE__.Service)
    assert :ok = SpeechToText.push_audio(ctx.capability, %{ctx.frame | sequence_number: 2})
  end

  test "disable revokes capture and re-enable starts a fresh partial run", ctx do
    start_port()
    start_room(ctx)
    attach(ctx)
    input = :sys.get_state(ctx.capability).diagnostic_tap.handoff
    monitor = Process.monitor(input.receiver)
    enable(ctx.settings, false, 2)

    assert %{pending?: false, last_reason: :settings_unavailable} =
             RoomService.scan(__MODULE__.Service)

    send(input.receiver, :check_grant)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    refute CaptureHandoff.current?(input)
    enable(ctx.settings, true, 3)
    attach(%{ctx | frame: %{ctx.frame | sequence_number: 2}})
    assert :sys.get_state(ctx.capability).diagnostic_tap.handoff.token != input.token
  end

  test "restart reconciles the same input and exhausted diagnostics leave the call open", ctx do
    start_port()
    supervisor = start_room(ctx)
    attach(ctx)
    input = :sys.get_state(ctx.capability).diagnostic_tap.handoff
    worker_monitor = Process.monitor(input.receiver)
    previous = Process.whereis(__MODULE__.Service)
    monitor = Process.monitor(previous)
    Process.exit(previous, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^previous, :killed}
    assert_receive {:DOWN, ^worker_monitor, :process, _, _}, 1_000
    _replacement = replacement(supervisor, previous, System.monotonic_time(:millisecond) + 1_000)
    attach(%{ctx | frame: %{ctx.frame | sequence_number: 2}})
    assert :sys.get_state(ctx.capability).diagnostic_tap.handoff.token != input.token
    previous = Process.whereis(__MODULE__.Service)
    Process.exit(previous, :kill)
    _replacement = replacement(supervisor, previous, System.monotonic_time(:millisecond) + 1_000)
    monitor = Process.monitor(supervisor)
    Process.exit(Process.whereis(__MODULE__.Service), :kill)
    assert_receive {:DOWN, ^monitor, :process, ^supervisor, :shutdown}, 1_000

    assert {:ok, %{sources: [_]}} =
             Vxpipe.CallEngine.RoomAuthority.DiagnosticInputs.query(ctx.room)

    assert :ok = SpeechToText.push_audio(ctx.capability, %{ctx.frame | sequence_number: 3})
    assert_receive {:scribe_audio, _, _}
  end

  test "shared capacity exhaustion reports its reason and retries after capacity is freed", ctx do
    {:ok, held} = SourceAdmission.reserve(__MODULE__.Admission, self())
    start_port()
    start_room(ctx)
    assert %{pending?: true} = RoomService.scan(__MODULE__.Service)
    assert :ok = SpeechToText.push_audio(ctx.capability, ctx.frame)
    assert %{active_sources: 0, last_reason: :capacity_unavailable} = settled()
    refute_received {:collector_started, _}
    :ok = SourceAdmission.cancel(__MODULE__.Admission, held)
    # Finish the current snapshot page; next pass starts from its first source.
    _ = RoomService.scan(__MODULE__.Service)
    attach(%{ctx | frame: %{ctx.frame | sequence_number: 2}})
  end

  test "two rooms share one source slot and the waiting room attaches after retirement", ctx do
    second = second_input(ctx)
    start_port()
    start_room(ctx)
    attach(ctx)
    first = :sys.get_state(ctx.capability).diagnostic_tap.handoff

    start_supervised!(
      {RoomSupervisor,
       name: __MODULE__.SecondDiagnostics,
       service: __MODULE__.SecondService,
       workers: __MODULE__.SecondWorkers,
       runner: __MODULE__.SecondRunner,
       room: second.room,
       port: __MODULE__.Port,
       source_admission: __MODULE__.Admission,
       poll_interval_ms: 1_000}
    )

    assert %{pending?: true} = RoomService.scan(__MODULE__.SecondService)
    assert :ok = SpeechToText.push_audio(second.capability, second.frame)

    assert %{active_sources: 0, last_reason: :capacity_unavailable} =
             settled(__MODULE__.SecondService, System.monotonic_time(:millisecond) + 2_000)

    refute_received {:collector_started, _}
    assert CaptureHandoff.current?(first)
    assert DynamicSupervisor.which_children(__MODULE__.SecondWorkers) == []
    monitor = Process.monitor(first.receiver)
    :sys.replace_state(ctx.room, &%{&1 | connections: %{}})
    RoomService.notify(__MODULE__.Service)
    _ = RoomService.scan(__MODULE__.Service)
    send(first.receiver, :check_grant)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    _ = RoomService.scan(__MODULE__.SecondService)
    assert %{pending?: true} = RoomService.scan(__MODULE__.SecondService)
    assert :ok = SpeechToText.push_audio(second.capability, %{second.frame | sequence_number: 2})
    assert_receive {:collector_started, context}, 1_000
    assert context.identity.room_id == "second-room"

    assert %{active_sources: 1} =
             settled(__MODULE__.SecondService, System.monotonic_time(:millisecond) + 2_000)

    assert %{active_sources: 1, occupied_slots: 1} = SourceAdmission.status(__MODULE__.Admission)
    assert :ok = SpeechToText.push_audio(ctx.capability, %{ctx.frame | sequence_number: 2})
  end

  test "stalled attachment runner leaves the service responsive and cannot start expired work",
       ctx do
    start_port()
    start_room(ctx)
    assert %{pending?: true} = RoomService.scan(__MODULE__.Service)
    :ok = :sys.suspend(__MODULE__.RoomRunner)

    try do
      assert :ok = SpeechToText.push_audio(ctx.capability, ctx.frame)
      wait_slots(1, System.monotonic_time(:millisecond) + 1_000)
      wait_slots(0, System.monotonic_time(:millisecond) + 1_000)
      assert %{active_sources: 0, pending?: false} = settled()
      for _ <- 1..3, do: RoomService.scan(__MODULE__.Service)
      assert %{occupied_slots: 0} = SourceAdmission.status(__MODULE__.Admission)
      refute_received {:collector_started, _}
    after
      :sys.resume(__MODULE__.RoomRunner)
    end

    _ = :sys.get_state(__MODULE__.RoomRunner)
    _ = RoomService.status(__MODULE__.Service)
    refute_received {:collector_started, _}
    _ = RoomService.scan(__MODULE__.Service)
    attach(%{ctx | frame: %{ctx.frame | sequence_number: 2}})
  end

  for vad <- [false, true], collection <- [false, true] do
    @tag local_vad: vad, collection: collection
    @vad vad
    @collection collection
    test "room input uses one inference path with local VAD #{@vad} and collection #{@collection}",
         ctx do
      start_port()
      start_room(ctx)
      frame = %{ctx.frame | payload: :binary.copy(<<0, 0>>, 512)}

      if ctx.collection do
        attach(%{ctx | frame: frame})
        worker = :sys.get_state(ctx.capability).diagnostic_tap.handoff.receiver

        assert :sys.get_state(worker).mode ==
                 if(ctx.local_vad, do: :operational_reuse, else: :benchmark_only)
      else
        assert %{active_sources: 0, pending?: false} = RoomService.scan(__MODULE__.Service)
        assert :ok = SpeechToText.push_audio(ctx.capability, frame)
        assert DynamicSupervisor.which_children(__MODULE__.RoomWorkers) == []
      end

      wire = ctx.wire
      initial_pcm = frame.payload
      assert_receive {:scribe_audio, ^wire, ^initial_pcm}, 1_000
      pcm = :binary.copy(<<7, 0>>, 512)

      assert :ok =
               SpeechToText.push_audio(ctx.capability, %{
                 frame
                 | payload: pcm,
                   sequence_number: 2,
                   timestamp: 512,
                   received_at: System.monotonic_time(:millisecond) + 32
               })

      assert_receive {:scribe_audio, ^wire, ^pcm}, 1_000

      cond do
        ctx.local_vad -> assert_receive {:matrix_inference, :operational, 512, ^pcm}, 1_000
        ctx.collection -> assert_receive {:matrix_inference, :benchmark, _, ^pcm}, 1_000
        true -> :ok
      end

      unexpected = if ctx.local_vad, do: :benchmark, else: :operational
      refute_receive {:matrix_inference, ^unexpected, _, ^pcm}, 100
      refute_received {:matrix_inference, _, _, ^pcm}
      refute_received {:scribe_audio, ^wire, ^pcm}
      refute_received {:scribe_commit, ^wire}

      if not ctx.collection do
        refute_received {:collector_started, _}
        refute_received {:matrix_inference, :benchmark, _, ^pcm}
      end

      old = :sys.get_state(ctx.capability).diagnostic_tap
      monitor = if old, do: Process.monitor(old.handoff.receiver)
      enable(ctx.settings, false, 2)

      assert %{pending?: false, last_reason: :settings_unavailable} =
               RoomService.scan(__MODULE__.Service)

      if old do
        send(old.handoff.receiver, :check_grant)
        assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
        refute CaptureHandoff.current?(old.handoff)
      end

      off_pcm = :binary.copy(<<8, 0>>, 512)

      assert :ok =
               SpeechToText.push_audio(ctx.capability, %{
                 frame
                 | payload: off_pcm,
                   sequence_number: 3,
                   timestamp: 1_024,
                   received_at: System.monotonic_time(:millisecond) + 32
               })

      assert_receive {:scribe_audio, ^wire, ^off_pcm}, 1_000

      if ctx.local_vad,
        do: assert_receive({:matrix_inference, :operational, 1_024, ^off_pcm}, 1_000)

      refute_receive {:matrix_inference, _, _, ^off_pcm}, 100
      assert DynamicSupervisor.which_children(__MODULE__.RoomWorkers) == []
      enable(ctx.settings, true, 3)

      restarted =
        attach(%{
          ctx
          | frame: %{
              frame
              | sequence_number: 4,
                timestamp: 1_536,
                received_at: System.monotonic_time(:millisecond) + 32
            }
        })

      assert_receive {:scribe_audio, ^wire, ^initial_pcm}, 1_000
      assert restarted.mode == if(ctx.local_vad, do: :operational_reuse, else: :benchmark_only)
      on_pcm = :binary.copy(<<9, 0>>, 512)

      assert :ok =
               SpeechToText.push_audio(ctx.capability, %{
                 frame
                 | payload: on_pcm,
                   sequence_number: 5,
                   timestamp: 2_048,
                   received_at: System.monotonic_time(:millisecond) + 32
               })

      assert_receive {:scribe_audio, ^wire, ^on_pcm}, 1_000
      expected = if ctx.local_vad, do: :operational, else: :benchmark
      assert_receive {:matrix_inference, ^expected, samples, ^on_pcm}, 1_000
      if ctx.local_vad, do: assert(samples == 2_048)
      refute_receive {:matrix_inference, _, _, ^on_pcm}, 100
      refute_received {:scribe_audio, ^wire, ^off_pcm}
      refute_received {:scribe_audio, ^wire, _}
      refute_received {:scribe_commit, ^wire}
    end
  end

  for initial_vad <- [false, true] do
    @tag local_vad: initial_vad
    @initial_vad initial_vad
    test "reconnecting STT replaces local VAD #{@initial_vad} with the other mode", ctx do
      start_port()
      start_room(ctx)
      frame = %{ctx.frame | payload: :binary.copy(<<0, 0>>, 512)}
      first = attach(%{ctx | frame: frame})
      first_wire = ctx.wire
      initial_pcm = frame.payload
      assert_receive {:scribe_audio, ^first_wire, ^initial_pcm}, 1_000
      old_input = :sys.get_state(ctx.capability).diagnostic_tap.handoff
      monitor = Process.monitor(old_input.receiver)
      replacement = replacement_input(ctx, not ctx.local_vad)

      :sys.replace_state(ctx.room, fn state ->
        connection = Map.fetch!(state.connections, "connection")

        %{
          state
          | connections:
              Map.put(state.connections, "connection", %{
                connection
                | speech_to_text: %{capability: replacement.capability}
              })
        }
      end)

      RoomService.notify(__MODULE__.Service)
      _ = RoomService.scan(__MODULE__.Service)
      send(old_input.receiver, :check_grant)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
      refute CaptureHandoff.current?(old_input)
      _ = RoomService.scan(__MODULE__.Service)
      second = attach(replacement)
      wire = replacement.wire
      assert_receive {:scribe_audio, ^wire, ^initial_pcm}, 1_000
      assert second.run_id != first.run_id
      assert second.generation != first.generation
      assert second.source_epoch != first.source_epoch
      assert second.mode == if(ctx.local_vad, do: :benchmark_only, else: :operational_reuse)

      assert %{occupied_slots: 1, active_sources: 1} =
               SourceAdmission.status(__MODULE__.Admission)

      assert length(DynamicSupervisor.which_children(__MODULE__.RoomWorkers)) == 1
      pcm = :binary.copy(<<11, 0>>, 512)

      assert :ok =
               SpeechToText.push_audio(replacement.capability, %{
                 replacement.frame
                 | payload: pcm,
                   sequence_number: 2,
                   timestamp: 512,
                   received_at: System.monotonic_time(:millisecond) + 32
               })

      assert_receive {:scribe_audio, ^wire, ^pcm}, 1_000
      expected = if ctx.local_vad, do: :benchmark, else: :operational
      assert_receive {:matrix_inference, ^expected, _, ^pcm}, 1_000
      refute_receive {:matrix_inference, _, _, ^pcm}, 100
      refute_received {:scribe_audio, _, _}
      refute_received {:scribe_commit, _}
    end
  end

  defp replacement_input(ctx, vad) do
    tree =
      start_supervised!({Vxpipe.CallEngine.Speech.CapabilityTree, owner: self()},
        id: :replacement_tree
      )

    {:ok, config} = Scribe.new(api_key: "synthetic", commit_strategy: :vad)
    {provider, private} = provider_options(%{local_vad: vad}, config, self())
    policy = :sys.get_state(ctx.capability).policy

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
         provider: provider,
         provider_private: private,
         initial_policy: policy},
        id: :replacement_capability
      )

    assert_receive {:scribe_started, wire}

    Wire.deliver_frame(
      wire,
      JSON.encode!(%{
        "message_type" => "session_started",
        "session_id" => "replacement",
        "config" => echoed_settings()
      })
    )

    assert_receive {:vxpipe_stt_signal, ^capability, _, _}, 1_000
    assert :ok = Enforcer.apply(capability, policy, 1_000)

    %{
      ctx
      | capability: capability,
        wire: wire,
        frame: %{ctx.frame | source_epoch: make_ref(), payload: :binary.copy(<<0, 0>>, 512)}
    }
  end

  defp provider_options(context, config, parent) do
    private = [config: config, wire_module: Wire, wire_options: [observer: parent]]

    if Map.has_key?(context, :local_vad) do
      {{Vxpipe.CallEngine.Speech.ConversationalSTT,
        [provider: STTSession, options: [commit_strategy: :vad], vad: context.local_vad]},
       [
         recognizer: STTSession,
         recognizer_options: [commit_strategy: :vad],
         recognizer_private: private,
         activity_options: [
           load: fn -> {:ok, :fixture_model} end,
           classify: classifier(parent, :operational)
         ]
       ]}
    else
      {{STTSession, [commit_strategy: :vad]}, private}
    end
  end

  defp classifier(parent, mode) do
    fn _model, stream, pcm ->
      send(parent, {:matrix_inference, mode, stream.samples, pcm})
      count = div(byte_size(pcm), 1_024)
      {:ok, %{stream | samples: stream.samples + count * 512}, List.duplicate(0.0, count)}
    end
  end

  defp wait_slots(expected, deadline) do
    case SourceAdmission.status(__MODULE__.Admission) do
      %{occupied_slots: ^expected} ->
        :ok

      other ->
        if System.monotonic_time(:millisecond) < deadline,
          do: wait_slots(expected, deadline),
          else: flunk("unexpected capacity: #{inspect(other)}")
    end
  end

  defp second_input(ctx) do
    tree =
      start_supervised!({Vxpipe.CallEngine.Speech.CapabilityTree, owner: self()},
        id: :second_tree
      )

    {:ok, config} = Scribe.new(api_key: "synthetic", commit_strategy: :vad)
    policy = :sys.get_state(ctx.capability).policy

    capability =
      start_supervised!(
        {SpeechToText,
         owner: self(),
         tenant_id: "tenant",
         room_id: "second-room",
         incarnation_id: "second-incarnation",
         participant_id: "human",
         connection_id: "connection",
         speech_scope: Vxpipe.CallEngine.Speech.CapabilityTree.scope(tree),
         provider: {STTSession, [commit_strategy: :vad]},
         provider_private: [config: config, wire_module: Wire, wire_options: [observer: self()]],
         initial_policy: policy},
        id: :second_capability
      )

    assert_receive {:scribe_started, wire}

    Wire.deliver_frame(
      wire,
      JSON.encode!(%{
        "message_type" => "session_started",
        "session_id" => "second",
        "config" => echoed_settings()
      })
    )

    assert_receive {:vxpipe_stt_signal, ^capability, _, _}
    assert :ok = Enforcer.apply(capability, policy, 1_000)
    state = room_state(capability)
    runtime = state.participant_transfer_runtime

    state = %{
      state
      | text_capability: nil,
        snapshot: %{state.snapshot | room_id: "second-room", incarnation_id: "second-incarnation"},
        participant_transfer_runtime: %{
          runtime
          | plan: %{runtime.plan | room_id: "second-room", call_id: "second-call"}
        }
    }

    room =
      start_supervised!(
        {DiagnosticRoomProbe,
         state: state, name: {:via, Registry, {__MODULE__.Rooms, {"tenant", "second-room"}}}},
        id: :second_room
      )

    %{
      room: room,
      capability: capability,
      frame: %{
        ctx.frame
        | room_id: "second-room",
          incarnation_id: "second-incarnation",
          source_epoch: make_ref()
      }
    }
  end

  test "a pending helper cannot bind after its source port is gone while service is suspended",
       ctx do
    parent = self()

    port =
      start_port(fn context ->
        send(parent, {:blocked_port_collector, self()})

        receive do
          :release ->
            CaptureHandoff.new(parent,
              owner: context.capability,
              projection: __MODULE__.Projection
            )
        end
      end)

    start_room(ctx)
    assert %{pending?: true} = RoomService.scan(__MODULE__.Service)
    assert :ok = SpeechToText.push_audio(ctx.capability, ctx.frame)
    assert_receive {:blocked_port_collector, helper}, 1_000
    :ok = :sys.suspend(__MODULE__.Service)

    try do
      port_monitor = Process.monitor(port)
      assert :ok = stop_supervised(SourcePort)
      assert_receive {:DOWN, ^port_monitor, :process, ^port, :shutdown}, 1_000
      send(helper, :release)
      _ = :sys.get_state(helper)
      assert DynamicSupervisor.which_children(__MODULE__.RoomWorkers) == []
      assert :sys.get_state(ctx.capability).diagnostic_tap == nil
    after
      :sys.resume(__MODULE__.Service)
    end
  end

  test "an adopted worker stops after port loss even while room service is suspended", ctx do
    port = start_port()
    start_room(ctx)
    attach(ctx)
    input = :sys.get_state(ctx.capability).diagnostic_tap.handoff
    worker_monitor = Process.monitor(input.receiver)
    :ok = :sys.suspend(__MODULE__.Service)

    try do
      port_monitor = Process.monitor(port)
      assert :ok = stop_supervised(SourcePort)
      assert_receive {:DOWN, ^port_monitor, :process, ^port, :shutdown}, 1_000
      send(input.receiver, :check_grant)
      assert_receive {:DOWN, ^worker_monitor, :process, _, _}, 500
      refute CaptureHandoff.current?(input)
    after
      :sys.resume(__MODULE__.Service)
    end
  end

  defp replacement(supervisor, previous, deadline) do
    case Enum.find(Supervisor.which_children(supervisor), &(elem(&1, 0) == RoomService)) do
      {RoomService, pid, _, _} when is_pid(pid) and pid != previous ->
        pid

      _ ->
        if System.monotonic_time(:millisecond) < deadline,
          do: replacement(supervisor, previous, deadline),
          else: flunk("service did not restart")
    end
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

  defp attach(ctx) do
    assert %{pending?: true} = RoomService.scan(__MODULE__.Service)
    assert :ok = SpeechToText.push_audio(ctx.capability, ctx.frame)
    assert_receive {:collector_started, context}, 1_000
    assert context.participant_id == "human"
    assert %{active_sources: 1} = settled()
    context
  end

  defp start_port(collector \\ nil) do
    parent = self()

    factory =
      collector ||
        fn context ->
          send(parent, {:collector_started, context})
          CaptureHandoff.new(parent, owner: context.capability, projection: __MODULE__.Projection)
        end

    start_supervised!(
      {SourcePort,
       name: __MODULE__.Port,
       projection: __MODULE__.Projection,
       runtime: __MODULE__.Runtime,
       maximum_sources: 1,
       collector: factory}
    )
  end

  defp start_room(ctx) do
    start_supervised!(
      {RoomSupervisor,
       name: __MODULE__.RoomDiagnostics,
       service: __MODULE__.Service,
       workers: __MODULE__.RoomWorkers,
       runner: __MODULE__.RoomRunner,
       room: ctx.room,
       port: __MODULE__.Port,
       source_admission: __MODULE__.Admission,
       poll_interval_ms: 1_000}
    )
  end

  defp settled, do: settled(__MODULE__.Service, System.monotonic_time(:millisecond) + 2_000)

  defp settled(service, deadline) do
    status = RoomService.status(service)

    if status.pending? and System.monotonic_time(:millisecond) < deadline,
      do: settled(service, deadline),
      else: status
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
