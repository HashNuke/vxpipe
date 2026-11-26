defmodule Vxpipe.CallEngine.RoomRecordingCandidateNamingTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{
    CallSpec,
    CallInvocation,
    CallSpecCompiler,
    RoomMixer,
    RoomRecording,
    TestRecordingWriter
  }

  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Snapshot}

  test "candidate shares participant keys and reconnect numbering with live tracks" do
    context = start_context()
    live_stream = context.live_stream

    assert live_stream.mode == track(context.caller, "connection-#{context.caller}")
    assert live_stream.participant_key == "caller"
    assert live_stream.reconnection == 0

    reconnect =
      {:individual_track, context.caller, "connection-#{context.caller}-2",
       "track-#{context.caller}-2"}

    joining = track(context.joining)

    assert {:ok, _prepared} =
             RoomRecording.prepare_policy(
               context.recording,
               context.candidate,
               Enum.sort([track(context.caller), reconnect, joining]),
               context.options
             )

    assert_receive {:test_recording_writer_opened, _caller, _source,
                    %{mode: ^joining} = joining_stream}

    assert joining_stream.participant_key == "joining"
    assert joining_stream.reconnection == 0

    assert_receive {:test_recording_writer_opened, _caller, _source,
                    %{mode: ^reconnect} = reconnect_stream}

    assert reconnect_stream.participant_key == "caller"
    assert reconnect_stream.reconnection == 1

    titles =
      Enum.map([live_stream, joining_stream, reconnect_stream], fn stream ->
        track_name(stream)
      end)

    assert titles == ["caller", "joining", "caller-1"]
    assert length(Enum.uniq(titles)) == length(titles)
  end

  test "aborted candidate retry keeps keys and numbering without duplicates" do
    context = start_context()

    reconnect =
      {:individual_track, context.caller, "connection-#{context.caller}-2",
       "track-#{context.caller}-2"}

    joining = track(context.joining)
    wanted = Enum.sort([track(context.caller), reconnect, joining])

    assert {:ok, prepared} =
             RoomRecording.prepare_policy(
               context.recording,
               context.candidate,
               wanted,
               context.options
             )

    assert_receive {:test_recording_writer_opened, first_joining_source, first_joining_source,
                    %{mode: ^joining}}

    assert_receive {:test_recording_writer_opened, first_reconnect_source, first_reconnect_source,
                    %{mode: ^reconnect}}

    first_monitors =
      Enum.map([first_joining_source, first_reconnect_source], &Process.monitor/1)

    assert :ok = RoomRecording.discard_policy(context.recording, prepared.token)

    for monitor <- first_monitors do
      assert_receive {:DOWN, ^monitor, :process, _pid, _reason}, 1_000
    end

    assert {:ok, _retried} =
             RoomRecording.prepare_policy(
               context.recording,
               context.candidate,
               wanted,
               context.options
             )

    assert_receive {:test_recording_writer_opened, second_joining_source, second_joining_source,
                    %{mode: ^joining} = joining_stream}

    assert_receive {:test_recording_writer_opened, second_reconnect_source,
                    second_reconnect_source, %{mode: ^reconnect} = reconnect_stream}

    assert joining_stream.participant_key == "joining"
    assert joining_stream.reconnection == 0
    assert reconnect_stream.participant_key == "caller"
    assert reconnect_stream.reconnection == 1
    refute second_joining_source in [first_joining_source, first_reconnect_source]
    refute second_reconnect_source in [first_joining_source, first_reconnect_source]

    titles = Enum.map([joining_stream, reconnect_stream], &track_name/1)

    assert titles == ["joining", "caller-1"]
    assert length(Enum.uniq(titles)) == length(titles)
  end

  test "changed candidate preserves staged suffix while allocating a distinct one" do
    context = start_context()
    caller = context.caller

    z = {:individual_track, caller, "connection-#{caller}-z", "track-#{caller}-z"}
    a = {:individual_track, caller, "connection-#{caller}-a", "track-#{caller}-a"}
    live_track = track(caller)

    assert Enum.sort([a, z]) == [a, z]

    assert {:ok, _} =
             RoomRecording.prepare_policy(
               context.recording,
               context.candidate,
               Enum.sort([live_track, z]),
               context.options
             )

    assert_receive {:test_recording_writer_opened, _caller, _source, %{mode: ^z} = z_stream},
                   1_000

    assert z_stream.reconnection == 1

    assert {:ok, _} =
             RoomRecording.prepare_policy(
               context.recording,
               context.candidate,
               Enum.sort([live_track, a, z]),
               context.options
             )

    assert_receive {:test_recording_writer_opened, _caller, _source, %{mode: ^a} = a_stream},
                   1_000

    assert a_stream.reconnection == 2
    assert a_stream.reconnection != z_stream.reconnection
  end

  test "hole after a removed suffix is reused" do
    context = start_context()
    caller = context.caller

    z = {:individual_track, caller, "connection-#{caller}-z", "track-#{caller}-z"}
    a = {:individual_track, caller, "connection-#{caller}-a", "track-#{caller}-a"}
    live_track = track(caller)

    assert {:ok, _} =
             RoomRecording.prepare_policy(
               context.recording,
               context.candidate,
               Enum.sort([live_track, z]),
               context.options
             )

    assert_receive {:test_recording_writer_opened, _caller, _source, %{mode: ^z} = z_stream},
                   1_000

    assert z_stream.reconnection == 1

    assert {:ok, _} =
             RoomRecording.prepare_policy(
               context.recording,
               context.candidate,
               Enum.sort([live_track]),
               context.options
             )

    assert {:ok, _} =
             RoomRecording.prepare_policy(
               context.recording,
               context.candidate,
               Enum.sort([live_track, a]),
               context.options
             )

    assert_receive {:test_recording_writer_opened, _caller, _source, %{mode: ^a} = a_stream},
                   1_000

    assert a_stream.reconnection == 1
  end

  test "idempotent refresh reuses staged outputs" do
    context = start_context()
    caller = context.caller

    z = {:individual_track, caller, "connection-#{caller}-z", "track-#{caller}-z"}
    live_track = track(caller)
    wanted = Enum.sort([live_track, z])

    assert {:ok, first_prepared} =
             RoomRecording.prepare_policy(
               context.recording,
               context.candidate,
               wanted,
               context.options
             )

    assert_receive {:test_recording_writer_opened, _caller, _source, %{mode: ^z} = z_stream},
                   1_000

    assert z_stream.reconnection == 1

    assert {:ok, second_prepared} =
             RoomRecording.prepare_policy(
               context.recording,
               context.candidate,
               wanted,
               context.options
             )

    assert first_prepared.token == second_prepared.token
    refute_receive {:test_recording_writer_opened, _, _, %{mode: ^z}}, 100
  end

  defp track_name(stream) do
    key = stream.participant_key || stream.participant_id
    if stream.reconnection > 0, do: "#{key}-#{stream.reconnection}", else: key
  end

  defp track(id, connection \\ nil) do
    connection = connection || "connection-#{id}"
    {:individual_track, id, connection, "track-#{id}"}
  end

  defp start_context do
    suffix = Integer.to_string(System.unique_integer([:positive, :monotonic]))
    incarnation = "recording-candidate-naming-#{suffix}"

    human = %{
      type: "human",
      connection: %{service: "web", mode: "receive", admission: "transfer"}
    }

    participants = Map.new(["caller", "joining", "observer"], &{&1, human})

    assert {:ok, call_spec} =
             CallSpec.new(
               %{
                 schema_version: "20260915.01",
                 media_policy: %{record_audio: true},
                 entry_caller: "caller",
                 entry_receiver: "joining",
                 defaults: %{capabilities: %{}},
                 participants: participants,
                 limits: %{max_duration_ms: 60_000}
               },
               resource_id: "recording-naming",
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: "recording-naming", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-recording",
               actor_id: "actor-recording",
               call_id: "call-#{suffix}",
               room_id: "room-#{suffix}"
             )

    assert {:ok, plan} =
             CallSpecCompiler.compile(call_spec, invocation, %{host_tools: %{}})

    authority =
      start_supervised!(
        Supervisor.child_spec({Authority, plan: plan, incarnation_id: incarnation},
          significant: false
        ),
        id: {:authority, suffix}
      )

    identities =
      Map.new([:caller, :joining, :observer], fn key ->
        {key, Map.fetch!(plan.participants, Atom.to_string(key)).participant_id}
      end)

    assert {:ok, base} = Authority.admit(authority, identities.caller)
    identity = %{tenant_id: plan.tenant_id, room_id: plan.room_id, incarnation_id: incarnation}
    recording_token = make_ref()

    mixer =
      start_supervised!(
        {RoomMixer,
         Map.to_list(identity) ++
           [
             recording_token: recording_token,
             sample_rate: 8_000,
             channels: 1,
             frame_samples: 2,
             maximum_buffered_timestamps: 4,
             maximum_sink_frames: 4,
             clock: fn -> 0 end,
             clock_origin_ms: 0
           ]},
        id: {:mixer, suffix}
      )

    assert {:ok, ^base} = Authority.register_enforcer(authority, mixer)

    participant_keys = %{
      identities.caller => "caller",
      identities.joining => "joining",
      identities.observer => "observer"
    }

    recording =
      start_supervised!(
        {RoomRecording,
         Map.to_list(identity) ++
           [
             call_id: plan.call_id,
             mixer: mixer,
             recording_token: recording_token,
             targets: [
               :room_track,
               {:individual_tracks, [identities.caller, identities.joining]}
             ],
             participant_keys: participant_keys,
             writer: {TestRecordingWriter, [observer: self()]},
             maximum_pull_frames: 4
           ]},
        id: {:recording, suffix}
      )

    assert :ok =
             RoomRecording.prepare_tracks(
               recording,
               [track(identities.caller), :room_track],
               Snapshot.interval(base, :recording)
             )

    assert_receive {:test_recording_writer_opened, _caller, ^recording, %{mode: :room_track}}

    assert_receive {:test_recording_writer_opened, _caller, ^recording,
                    %{mode: {:individual_track, _, _, _}} = live_stream}

    assert {:ok, candidate} =
             Authority.preview_presence(
               authority,
               MapSet.put(base.present_participant_ids, identities.joining)
             )

    Map.merge(identities, %{
      authority: authority,
      mixer: mixer,
      recording: recording,
      identity: identity,
      candidate: candidate,
      live_stream: live_stream,
      options: [
        owner: self(),
        attempt_id: "recording-naming",
        deadline_ms: System.monotonic_time(:millisecond) + 5_000
      ]
    })
  end
end
