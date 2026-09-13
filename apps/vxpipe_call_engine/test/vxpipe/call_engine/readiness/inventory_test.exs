defmodule Vxpipe.CallEngine.Readiness.InventoryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallDefinition, CallInvocation, DefinitionCompiler}
  alias Vxpipe.CallEngine.CallDefinition.CapabilitySelection
  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Effective, Snapshot}
  alias Vxpipe.CallEngine.Readiness.{Inventory, RoomInventory}
  alias Vxpipe.CallEngine.ResolvedCallPlan.Capabilities

  setup do
    plan = plan()

    ids =
      Map.new(plan.participants, fn {key, participant} -> {key, participant.participant_id} end)

    present =
      MapSet.new(Enum.map(["one", "two", "three", "four", "joining"], &Map.fetch!(ids, &1)))

    policy = %Snapshot{
      revision: 1,
      present_participant_ids: present,
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: :unrestricted,
        record_audio: true,
        save_transcripts: true
      }
    }

    connections =
      Map.new(ids, fn {key, id} -> {key, connection(id)} end)
      |> Map.put("one-second", connection(ids["one"]))
      |> Map.update!("four", &%{&1 | role: :monitor})
      |> Map.update!(
        "joining",
        &%{&1 | admission: :transfer_preparation, transfer_attempt_id: "attempt"}
      )

    %{plan: plan, ids: ids, policy: policy, connections: connections}
  end

  test "includes all resulting listeners and every authorized sink, excluding the departing source",
       context do
    assert {:ok, inventory} = build(context, attempt_id: "attempt")

    assert Map.keys(inventory.connections) |> Enum.sort() ==
             ["four", "joining", "one", "one-second", "three", "two"]

    assert inventory.missing_participants == MapSet.new()
    assert inventory.room == MapSet.new([:room_mixer, :transcript_router, :call_variables])

    assert inventory.connections["one"].demand ==
             [audio_input?: true, room_output?: true, speech_to_text?: true]

    assert inventory.connections["four"].demand ==
             [audio_input?: false, room_output?: true, speech_to_text?: false]

    assert inventory.connections["joining"].admission == :transfer_preparation
    assert inventory.participant_ids == context.policy.present_participant_ids
  end

  test "missing or foreign-attempt destinations remain required even when there is no actor",
       context do
    for connections <- [context.connections, Map.delete(context.connections, "joining")] do
      assert {:ok, inventory} = build(%{context | connections: connections}, attempt_id: "other")
      assert inventory.missing_participants == MapSet.new([context.ids["joining"]])
      refute Map.has_key?(inventory.connections, "joining")
    end
  end

  test "derives selected speech and audio demand from policy, not from running processes",
       context do
    effective = %{
      context.policy.effective
      | audio_routes: %{},
        transcript_routes: %{},
        record_audio: false,
        save_transcripts: false
    }

    denied = %{context | policy: %{context.policy | effective: effective}}
    assert {:ok, inventory} = build(denied, attempt_id: "attempt")

    assert Enum.all?(inventory.connections, fn {_id, request} ->
             request.demand == [audio_input?: false, room_output?: false, speech_to_text?: false]
           end)

    plan = context.plan
    plan = put_in(plan.participants["one"].capabilities, %Capabilities{})
    assert {:ok, inventory} = build(%{context | plan: plan}, attempt_id: "attempt")
    refute Keyword.fetch!(inventory.connections["one"].demand, :speech_to_text?)
    assert Keyword.fetch!(inventory.connections["two"].demand, :speech_to_text?)
  end

  test "enabled recording requires only the selected permitted microphone tracks", context do
    policy = %{context.policy | effective: %{context.policy.effective | audio_routes: %{}}}
    context = %{context | policy: policy}
    assert {:ok, disabled} = build(context, attempt_id: "attempt")

    refute Enum.any?(disabled.connections, fn {_id, request} ->
             Keyword.fetch!(request.demand, :audio_input?)
           end)

    settings = [enabled: true, targets: [{:individual_participants, ["two", "four"]}]]
    assert {:ok, enabled} = build(context, attempt_id: "attempt", recording: settings)
    assert MapSet.member?(enabled.room, :recording)
    assert Keyword.fetch!(enabled.connections["two"].demand, :audio_input?)
    refute Keyword.fetch!(enabled.connections["one"].demand, :audio_input?)
    refute Keyword.fetch!(enabled.connections["four"].demand, :audio_input?)
    assert enabled.recording_participant_ids == MapSet.new([context.ids["two"]])
  end

  test "keeps required room handoffs and remaining/incoming agent capabilities when no PID exists",
       context do
    plan = Enum.reduce(["two", "joining", "departing"], context.plan, &agent/2)

    assert {:ok, inventory} =
             build(%{context | plan: plan}, archive?: true, live_inspection?: true)

    assert inventory.participant_capabilities == %{
             context.ids["two"] => MapSet.new([:model_inference, :text_to_speech]),
             context.ids["joining"] => MapSet.new([:model_inference, :text_to_speech])
           }

    assert MapSet.subset?(MapSet.new([:archive, :live_inspection]), inventory.room)
    refute Map.has_key?(inventory.connections, "two")
    refute Map.has_key?(inventory.connections, "joining")
    assert inventory.missing_participants == MapSet.new()
  end

  test "uses a prospective policy preview while the source remains live and leaves it unchanged",
       context do
    authority =
      [plan: context.plan, incarnation_id: "inventory", register: false]
      |> Authority.child_spec()
      |> Map.put(:significant, false)
      |> start_supervised!()

    source = context.ids["departing"]

    for id <-
          MapSet.put(context.policy.present_participant_ids, source)
          |> MapSet.delete(context.ids["joining"]) do
      assert {:ok, _} = Authority.admit(authority, id)
    end

    before = Authority.snapshot(authority)

    assert {:ok, candidate} =
             Authority.preview_presence(authority, context.policy.present_participant_ids)

    assert {:ok, inventory} =
             build(%{context | policy: candidate.snapshot}, attempt_id: "attempt")

    refute MapSet.member?(inventory.participant_ids, source)
    assert Authority.snapshot(authority) == before

    assert {:ok, ^inventory} =
             build(%{context | policy: candidate.snapshot}, attempt_id: "attempt")
  end

  test "rejects unplanned membership and unknown recording targets instead of returning a partial set",
       context do
    policy = %{
      context.policy
      | present_participant_ids: MapSet.put(context.policy.present_participant_ids, "foreign")
    }

    assert {:error, :unknown_participant} = build(%{context | policy: policy})

    assert {:error, :invalid_recording_targets} =
             build(context,
               recording: [enabled: true, targets: [{:individual_participants, ["foreign"]}]]
             )
  end

  test "accepts pinned recording IDs and rejects target shapes the recorder cannot initialize",
       context do
    target = {:individual_tracks, [context.ids["two"]]}
    assert {:ok, inventory} = build(context, recording: [enabled: true, targets: [target]])
    assert inventory.recording_targets == [target]

    for targets <- [
          nil,
          [],
          [:unknown],
          [:full_mix, :full_mix],
          [{:individual_tracks, []}],
          [{:individual_tracks, ["foreign"]}],
          [{:individual_participants, ["one", "one"]}],
          [target, {:individual_participants, ["one"]}]
        ] do
      assert {:error, :invalid_recording_targets} =
               build(context, recording: [enabled: true, targets: targets])
    end
  end

  defp build(context, options \\ []) do
    Inventory.build(context.plan, context.policy, context.connections, options)
  end

  test "captures the enabled room bindings without losing required disconnected participants",
       context do
    %{room: room, policy: authority, plan: plan} = start_room(context.plan, recording?: true)
    policy = Authority.snapshot(authority)

    assert {:ok, candidate} =
             Authority.preview_presence(authority, policy.present_participant_ids)

    assert {:ok, captured} = RoomInventory.capture(room, candidate)
    assert captured.inventory.missing_participants == policy.present_participant_ids

    assert captured.inventory.room ==
             MapSet.new([
               :room_mixer,
               :transcript_router,
               :call_variables,
               :live_inspection,
               :recording
             ])

    assert Enum.all?(captured.room, fn {_kind, pid} -> is_pid(pid) end)

    assert {:ok, resource, :ready} =
             Vxpipe.CallEngine.RoomRecording.readiness(captured.room.recording)

    assert resource.instance == captured.room.recording
    assert captured.identity.room_id == plan.room_id
    assert :ok = RoomInventory.validate(room, captured)
    assert {:ok, again} = RoomInventory.capture(room, candidate)
    assert again == captured
  end

  test "rejects foreign or stale policy evidence while retaining the authoritative inventory",
       context do
    %{room: room, policy: authority} = start_room(context.plan)
    policy = Authority.snapshot(authority)

    assert {:ok, candidate} =
             Authority.preview_presence(authority, policy.present_participant_ids)

    assert {:ok, captured} = RoomInventory.capture(room, candidate)
    refute Map.has_key?(captured.room, :recording)

    assert {:error, :invalid_candidate} =
             RoomInventory.capture(room, %{candidate | authority: self()})

    assert {:ok, _} = Authority.admit(authority, context.ids["joining"])
    assert {:error, :stale_candidate} = RoomInventory.validate(room, captured)
    assert {:error, :stale_candidate} = RoomInventory.capture(room, candidate)
  end

  test "validation rejects an inventory with an enabled room requirement removed", context do
    %{room: room, policy: authority} = start_room(context.plan)
    policy = Authority.snapshot(authority)

    assert {:ok, candidate} =
             Authority.preview_presence(authority, policy.present_participant_ids)

    assert {:ok, captured} = RoomInventory.capture(room, candidate)
    shortened = %{captured | room: Map.delete(captured.room, :live_inspection)}
    assert {:error, :invalid_inventory} = RoomInventory.validate(room, shortened)
  end

  test "a missing enabled recorder remains required and invalidates its previous binding",
       context do
    %{room: room, policy: authority, supervisor: supervisor} =
      start_room(context.plan, recording?: true)

    policy = Authority.snapshot(authority)

    assert {:ok, candidate} =
             Authority.preview_presence(authority, policy.present_participant_ids)

    assert {:ok, captured} = RoomInventory.capture(room, candidate)
    recording = captured.room.recording
    monitor = Process.monitor(recording)

    assert :ok =
             Supervisor.terminate_child(
               supervisor,
               {Vxpipe.CallEngine.RoomRecording, captured.identity.incarnation_id}
             )

    assert_receive {:DOWN, ^monitor, :process, ^recording, :shutdown}
    assert {:error, :room_changed} = RoomInventory.validate(room, captured)
    assert {:ok, current} = RoomInventory.capture(room, candidate)
    assert MapSet.member?(current.inventory.room, :recording)
    assert Map.fetch(current.room, :recording) == {:ok, nil}
  end

  test "a busy policy authority cannot block the room binding callback and capture stays bounded",
       context do
    %{room: room, policy: authority} = start_room(context.plan)
    policy = Authority.snapshot(authority)

    assert {:ok, candidate} =
             Authority.preview_presence(authority, policy.present_participant_ids)

    :ok = :sys.suspend(authority)

    try do
      assert {:ok, _binding} = Vxpipe.CallEngine.RoomAuthority.readiness_binding(room)
      assert {:error, :unavailable} = RoomInventory.capture(room, candidate, 50)
      assert {:ok, _binding} = Vxpipe.CallEngine.RoomAuthority.readiness_binding(room)
    after
      :ok = :sys.resume(authority)
    end

    assert {:ok, _captured} = RoomInventory.capture(room, candidate)
  end

  defp start_room(plan, options \\ []) do
    alias Vxpipe.CallEngine.{RoomAuthority, RoomIncarnationSupervisor, TestRecordingWriter}

    participants =
      Map.new(plan.participants, fn {key, participant} ->
        {key, %{participant | capabilities: %Capabilities{}}}
      end)

    plan = %{plan | participants: participants}
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)
    assert {:ok, opening_audio} = Vxpipe.CallEngine.OpeningAudio.Settings.new([])
    incarnation = "inventory-#{System.unique_integer([:positive])}"

    recording = [
      enabled: Keyword.get(options, :recording?, false),
      targets: [:full_mix],
      writer: {TestRecordingWriter, observer: self()},
      maximum_pull_frames: 20
    ]

    options =
      Keyword.take(settings, [:call_lifecycle, :room_mixer, :transcript_router, :live_inspection]) ++
        [
          plan: plan,
          incarnation_id: incarnation,
          start_command_id: "inventory-start",
          opening_audio: opening_audio,
          recording: recording
        ]

    supervisor = start_supervised!({RoomIncarnationSupervisor, options})
    snapshot = RoomAuthority.snapshot(plan.tenant_id, plan.room_id)
    [{room, _}] = Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    %{
      room: room,
      policy: Authority.whereis(snapshot.incarnation_id),
      plan: plan,
      supervisor: supervisor
    }
  end

  defp connection(participant_id) do
    %{
      participant_id: participant_id,
      pid: self(),
      role: :human,
      admission: :main,
      transfer_attempt_id: nil
    }
  end

  defp agent(key, plan) do
    participant = Map.fetch!(plan.participants, key)

    capabilities = %Capabilities{
      model_inference: selection(:model_inference),
      text_to_speech: selection(:text_to_speech)
    }

    participant = %{
      participant
      | kind: :agent,
        activation_id: "activation-#{key}",
        connection: nil,
        capabilities: capabilities
    }

    %{plan | participants: Map.put(plan.participants, key, participant)}
  end

  defp plan do
    participants =
      Map.new(["one", "two", "three", "four", "departing", "joining", "unused"], fn key ->
        {key,
         %{type: "human", connection: %{service: "web", mode: "receive", admission: "start_call"}}}
      end)

    assert {:ok, definition} =
             CallDefinition.new(
               %{
                 schema_version: CallDefinition.schema_version(),
                 entry_caller: "one",
                 entry_receiver: "departing",
                 participants: participants
               },
               resource_id: "inventory",
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{call_definition: %{id: "inventory", revision: 1}, transport: %{type: "web"}},
               tenant_id: "tenant",
               actor_id: "actor"
             )

    assert {:ok, plan} =
             DefinitionCompiler.compile(definition, invocation, %{
               capability_profiles: %{},
               host_tools: %{}
             })

    participants =
      Map.new(plan.participants, fn {key, participant} ->
        {key,
         %{participant | capabilities: %Capabilities{speech_to_text: selection(:speech_to_text)}}}
      end)

    %{plan | participants: participants}
  end

  defp selection(kind) do
    %CapabilitySelection{
      kind: kind,
      profile: "selected-#{kind}",
      provider: :fixture,
      options: %{}
    }
  end
end
