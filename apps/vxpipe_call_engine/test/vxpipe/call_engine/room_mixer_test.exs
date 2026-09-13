defmodule Vxpipe.CallEngine.RoomMixerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Media.{EgressAcceptedFrame, MixedFrame, NormalizedFrame}
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.CallEngine.Recording.EgressHandoff
  alias Vxpipe.CallEngine.RoomMixer
  alias Vxpipe.CallEngine.RoomMixer.Subscription

  @identity %{
    tenant_id: "tenant-mixer",
    room_id: "room-mixer",
    incarnation_id: "incarnation-mixer"
  }

  test "aligns PCM sources and emits policy-filtered mix-minus, full-mix, and track output" do
    mixer = start_mixer()
    :ok = apply_policy(mixer, 0, ["alice", "bob", "monitor", "debugger"])

    assert {:ok, alice} = subscribe(mixer, "alice-output", "alice", :mix_minus)
    assert {:ok, bob} = subscribe(mixer, "bob-output", "bob", :mix_minus)
    assert {:ok, monitor} = subscribe(mixer, "monitor-output", "monitor", :full_mix)

    assert {:ok, debugger} =
             subscribe(mixer, "debugger-output", "debugger", {:individual_track, "alice"})

    assert {:error, :source_not_authorized} =
             RoomMixer.push(mixer, frame("monitor", 1, 0, [9_000, 9_000]))

    assert :ok = RoomMixer.push(mixer, frame("alice", 1, 0, [1_000, 2_000]))
    assert :ok = RoomMixer.push(mixer, frame("bob", 1, 0, [3_000, -5_000]))

    assert {:ok, %{delivered: 4, dropped: 0, flushed_timestamps: 1}} =
             RoomMixer.flush_through(mixer, 0)

    assert_frame(Subscription.take(alice, 4), "alice", ["bob"], [3_000, -5_000], 0)
    assert_frame(Subscription.take(bob, 4), "bob", ["alice"], [1_000, 2_000], 0)

    assert_frame(
      Subscription.take(monitor, 4),
      "monitor",
      ["alice", "bob"],
      [4_000, -3_000],
      0
    )

    assert_frame(Subscription.take(debugger, 4), "debugger", ["alice"], [1_000, 2_000], 0)
  end

  test "keeps simultaneous connection tracks for one participant distinct" do
    mixer = start_mixer()
    :ok = apply_policy(mixer, 0, ["alice", "monitor"])
    assert {:ok, monitor} = subscribe(mixer, "monitor-output", "monitor", :full_mix)

    assert :ok =
             RoomMixer.push(
               mixer,
               frame("alice", 1, 0, [1_000, 2_000],
                 connection_id: "connection-a",
                 track_id: "track-a"
               )
             )

    assert :ok =
             RoomMixer.push(
               mixer,
               frame("alice", 1, 0, [3_000, -5_000],
                 connection_id: "connection-b",
                 track_id: "track-b"
               )
             )

    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 0)
    assert_frame(Subscription.take(monitor, 1), "monitor", ["alice"], [4_000, -3_000], 0)
  end

  test "preserves buffered and queued live and recording audio across unrelated revisions" do
    token = make_ref()
    mixer = start_mixer(recording_token: token)
    :ok = apply_policy(mixer, 0, ["alice", "bob"])
    assert {:ok, alice} = subscribe(mixer, "alice-output", "alice", :mix_minus)
    assert {:ok, recording} = subscribe_recording(mixer, token, :full_mix)
    assert :ok = RoomMixer.push(mixer, frame("bob", 1, 0, [100, 200]))
    assert {:ok, %{delivered: 2}} = RoomMixer.flush_through(mixer, 0)
    assert :ok = RoomMixer.push(mixer, frame("bob", 2, 2, [300, 400]))

    :ok = apply_policy(mixer, 1, ["alice", "bob", "support"])
    :ok = apply_policy(mixer, 2, ["alice", "bob", "support"], transcript_routes: %{})
    assert_frame(Subscription.take(alice, 1), "alice", ["bob"], [100, 200], 0)
    assert_frame(Subscription.take(recording, 1), nil, ["bob"], [100, 200], 0)
    assert {:ok, %{delivered: 2}} = RoomMixer.flush_through(mixer, 2)
    assert_frame(Subscription.take(alice, 1), "alice", ["bob"], [300, 400], 0)
    assert_frame(Subscription.take(recording, 1), nil, ["bob"], [300, 400], 0)
    assert :ok = RoomMixer.push(mixer, frame("bob", 3, 4, [500, 600]))
    assert %{policy_dropped_frames: 0} = RoomMixer.stats(mixer)
  end

  test "applies a new policy revision before acknowledging it and never replays queued media" do
    mixer = start_mixer()
    :ok = apply_policy(mixer, 0, ["alice", "bob", "monitor"])

    assert {:ok, alice} = subscribe(mixer, "alice-output", "alice", :mix_minus)
    assert {:ok, monitor} = subscribe(mixer, "monitor-output", "monitor", :full_mix)

    assert :ok = RoomMixer.push(mixer, frame("bob", 1, 0, [100, 200]))

    routes = %{"bob" => MapSet.new(["alice"])}
    :ok = apply_policy(mixer, 1, ["alice", "bob", "monitor"], audio_routes: routes)

    assert {:error, :stale_policy_revision} =
             RoomMixer.push(mixer, frame("bob", 2, 0, [300, 400], policy_revision: 0))

    assert :ok =
             RoomMixer.push(mixer, frame("bob", 2, 0, [300, 400], policy_revision: 1))

    assert {:ok, %{delivered: 1, dropped: 0}} = RoomMixer.flush_through(mixer, 0)
    assert_frame(Subscription.take(alice, 4), "alice", ["bob"], [300, 400], 1)
    assert {:ok, []} = Subscription.take(monitor, 4)

    :ok = apply_policy(mixer, 2, ["alice", "bob", "monitor"])
    assert {:ok, []} = Subscription.take(alice, 4)

    assert :ok =
             RoomMixer.push(mixer, frame("bob", 3, 2, [500, 600], policy_revision: 2))

    assert {:ok, %{delivered: 2, dropped: 0}} = RoomMixer.flush_through(mixer, 2)
    assert_frame(Subscription.take(alice, 4), "alice", ["bob"], [500, 600], 2)
    assert_frame(Subscription.take(monitor, 4), "monitor", ["bob"], [500, 600], 2)

    assert %{policy_dropped_frames: 1, policy_revision: 2} = RoomMixer.stats(mixer)
  end

  test "records only permitted policy intervals through an authorized internal subscription" do
    recording_token = make_ref()
    mixer = start_mixer(recording_token: recording_token)

    :ok =
      apply_policy(mixer, 0, ["alice", "bob"],
        audio_routes: %{},
        record_audio: true
      )

    assert {:error, :recording_not_authorized} =
             subscribe_recording(mixer, make_ref(), :full_mix)

    assert {:ok, recording} = subscribe_recording(mixer, recording_token, :full_mix)

    assert :ok = RoomMixer.push(mixer, frame("alice", 1, 0, [1_000, 2_000]))
    assert :ok = RoomMixer.push(mixer, frame("bob", 1, 0, [3_000, -5_000]))
    assert {:ok, %{delivered: 1, dropped: 0}} = RoomMixer.flush_through(mixer, 0)
    assert_frame(Subscription.take(recording, 1), nil, ["alice", "bob"], [4_000, -3_000], 0)

    :ok = apply_policy(mixer, 1, ["alice", "bob"], record_audio: false)

    assert :ok =
             RoomMixer.push(mixer, frame("alice", 2, 2, [5_000, 6_000], policy_revision: 1))

    assert {:ok, %{delivered: 0, dropped: 0}} = RoomMixer.flush_through(mixer, 2)
    assert {:ok, []} = Subscription.take(recording, 1)

    :ok = apply_policy(mixer, 2, ["alice", "bob"], record_audio: true)

    assert :ok =
             RoomMixer.push(mixer, frame("bob", 2, 4, [7_000, 8_000], policy_revision: 2))

    assert {:ok, %{delivered: 1, dropped: 0}} = RoomMixer.flush_through(mixer, 4)
    assert_frame(Subscription.take(recording, 1), nil, ["bob"], [7_000, 8_000], 2)
  end

  test "adds accepted direct egress only to permitted recording output" do
    recording_token = make_ref()

    mixer =
      start_mixer(
        recording_token: recording_token,
        maximum_recording_egress_frames: 2,
        clock_origin_ms: 1_000,
        clock: fn -> 1_000 end
      )

    :ok = apply_policy(mixer, 0, ["alice", "agent", "bob"], record_audio: true)
    assert {:ok, listener} = subscribe(mixer, "alice-output", "alice", :full_mix)
    assert {:ok, recording} = subscribe_recording(mixer, recording_token, :full_mix)

    assert {:ok, handoff} = RoomMixer.open_recording_egress(mixer, "connection-alice")

    assert :ok =
             EgressHandoff.offer(
               handoff,
               egress_frame("agent", "connection-alice", [300, 400])
             )

    _ = :sys.get_state(mixer)
    assert :ok = RoomMixer.push(mixer, frame("bob", 1, 0, [100, 200]))
    assert {:ok, %{delivered: 2}} = RoomMixer.flush_through(mixer, 0)

    assert_frame(Subscription.take(listener, 1), "alice", ["bob"], [100, 200], 0)

    assert_frame(
      Subscription.take(recording, 1),
      nil,
      ["agent", "bob"],
      [400, 600],
      0
    )

    :ok = apply_policy(mixer, 1, ["alice", "agent", "bob"], record_audio: false)

    assert :ignored =
             EgressHandoff.offer(
               handoff,
               egress_frame("agent", "connection-alice", [500, 600])
             )

    assert %{recording_egress_rejected_frames: 0} = RoomMixer.stats(mixer)
  end

  test "bounds timestamp alignment and every subscriber queue without blocking the mixer" do
    mixer = start_mixer(maximum_buffered_timestamps: 1, maximum_sink_frames: 1)
    :ok = apply_policy(mixer, 0, ["alice", "bob"])
    assert {:ok, alice} = subscribe(mixer, "alice-output", "alice", :mix_minus)

    assert :ok = RoomMixer.push(mixer, frame("bob", 1, 0, [100, 200]))
    assert {:error, :buffer_full} = RoomMixer.push(mixer, frame("bob", 2, 2, [300, 400]))
    assert {:ok, %{delivered: 1, dropped: 0}} = RoomMixer.flush_through(mixer, 0)

    assert :ok = RoomMixer.push(mixer, frame("bob", 2, 2, [300, 400]))
    assert {:error, :duplicate_frame} = RoomMixer.push(mixer, frame("bob", 3, 2, [500, 600]))
    assert {:ok, %{delivered: 0, dropped: 1}} = RoomMixer.flush_through(mixer, 2)

    assert_frame(Subscription.take(alice, 4), "alice", ["bob"], [100, 200], 0)

    assert {:error, :stale_timestamp} =
             RoomMixer.push(mixer, frame("bob", 3, 2, [500, 600]))

    assert %{buffer_overflows: 1, sink_overflows: 1} = RoomMixer.stats(mixer)
  end

  test "rejects an invalid enabled recording egress bound" do
    assert {:error, {{:invalid_room_mixer_option, :maximum_recording_egress_frames}, _child}} =
             start_supervised(
               {RoomMixer,
                mixer_options(
                  recording_token: make_ref(),
                  maximum_recording_egress_frames: 0
                )}
             )
  end

  test "rejects cross-room, absent-recipient, and conflicting monitor subscriptions" do
    mixer = start_mixer()
    :ok = apply_policy(mixer, 0, ["alice", "monitor"])

    assert {:error, :wrong_room} =
             subscribe(mixer, "wrong-room", "alice", :mix_minus, room_id: "other-room")

    assert {:error, :recipient_not_present} =
             subscribe(mixer, "absent", "missing", :mix_minus)

    assert {:ok, _monitor} = subscribe(mixer, "monitor", "monitor", :full_mix)

    assert {:error, :conflicting_subscription} =
             subscribe(mixer, "monitor-speaking", "monitor", :mix_minus)

    assert {:error, :duplicate_subscription} =
             subscribe(mixer, "monitor", "alice", :mix_minus)
  end

  test "saturates signed 16-bit samples while mixing" do
    mixer = start_mixer()
    :ok = apply_policy(mixer, 0, ["alice", "bob", "monitor"])
    assert {:ok, monitor} = subscribe(mixer, "monitor-output", "monitor", :full_mix)

    assert :ok = RoomMixer.push(mixer, frame("alice", 1, 0, [30_000, -30_000]))
    assert :ok = RoomMixer.push(mixer, frame("bob", 1, 0, [10_000, -10_000]))
    assert {:ok, %{delivered: 1}} = RoomMixer.flush_through(mixer, 0)

    assert_frame(Subscription.take(monitor, 4), "monitor", ["alice", "bob"], [32_767, -32_768], 0)
  end

  test "rejects malformed and non-monotonic policy snapshots" do
    mixer = start_mixer()

    malformed = %Snapshot{
      revision: 0,
      present_participant_ids: MapSet.new(["alice"]),
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: :unrestricted,
        record_audio: :sometimes,
        save_transcripts: true
      }
    }

    assert {:error, :invalid_policy} = Enforcer.apply(mixer, malformed, 1_000)
    :ok = apply_policy(mixer, 4, ["alice"])
    assert {:error, :stale_policy_revision} = apply_policy(mixer, 4, ["alice"])
    assert {:error, :unexpected_policy_revision} = apply_policy(mixer, 6, ["alice"])
  end

  test "retains but does not deliver to a subscription whose participant has left" do
    mixer = start_mixer()
    :ok = apply_policy(mixer, 0, ["alice", "bob"])
    assert {:ok, alice} = subscribe(mixer, "alice-output", "alice", :mix_minus)

    :ok = apply_policy(mixer, 1, ["bob"])
    assert :ok = RoomMixer.push(mixer, frame("bob", 1, 0, [100, 200], policy_revision: 0))
    assert {:ok, %{delivered: 0, dropped: 0}} = RoomMixer.flush_through(mixer, 0)
    assert {:ok, []} = Subscription.take(alice, 4)
  end

  test "flushes due timestamps from the room clock and keeps playout scheduled" do
    test_process = self()
    clock = start_supervised!({Agent, fn -> 1_000 end})

    schedule = fn target, message, delay_ms ->
      send(test_process, {:test_mixer_scheduled, target, message, delay_ms})
      make_ref()
    end

    mixer =
      start_mixer(
        clock_origin_ms: 1_000,
        clock: fn -> Agent.get(clock, & &1) end,
        playout_delay_ms: 40,
        schedule: schedule
      )

    assert_receive {:test_mixer_scheduled, ^mixer, first_tick, 1}
    :ok = apply_policy(mixer, 0, ["alice", "bob"])
    assert {:ok, alice} = subscribe(mixer, "alice-output", "alice", :mix_minus)
    assert :ok = RoomMixer.push(mixer, frame("bob", 1, 0, [100, 200]))

    send(mixer, first_tick)
    refute_receive {:vxpipe_room_audio_available, ^mixer, "alice-output"}
    assert_receive {:test_mixer_scheduled, ^mixer, due_tick, 1}

    Agent.update(clock, fn _now -> 1_040 end)
    send(mixer, due_tick)

    assert_receive {:vxpipe_room_audio_available, ^mixer, "alice-output"}
    assert_frame(Subscription.take(alice, 1), "alice", ["bob"], [100, 200], 0)
    assert_receive {:test_mixer_scheduled, ^mixer, _next_tick, 1}
  end

  defp start_mixer(overrides \\ []) do
    start_supervised!({RoomMixer, mixer_options(overrides)})
  end

  defp mixer_options(overrides) do
    Keyword.merge(
      [
        tenant_id: @identity.tenant_id,
        room_id: @identity.room_id,
        incarnation_id: @identity.incarnation_id,
        sample_rate: 8_000,
        channels: 1,
        frame_samples: 2,
        maximum_buffered_timestamps: 2,
        maximum_sink_frames: 4,
        register: false
      ],
      overrides
    )
  end

  defp apply_policy(mixer, revision, participants, overrides \\ []) do
    effective =
      struct!(
        Effective,
        Keyword.merge(
          [
            audio_routes: :unrestricted,
            transcript_routes: :unrestricted,
            record_audio: true,
            save_transcripts: true
          ],
          overrides
        )
      )

    snapshot = %Snapshot{
      revision: revision,
      present_participant_ids: MapSet.new(participants),
      effective: effective
    }

    Enforcer.apply(mixer, snapshot, 1_000)
  end

  defp subscribe(mixer, id, recipient, mode, overrides \\ []) do
    options =
      Keyword.merge(
        [
          id: id,
          tenant_id: @identity.tenant_id,
          room_id: @identity.room_id,
          incarnation_id: @identity.incarnation_id,
          recipient_participant_id: recipient,
          mode: mode,
          subscriber: self()
        ],
        overrides
      )

    RoomMixer.subscribe(mixer, options)
  end

  defp subscribe_recording(mixer, recording_token, mode) do
    RoomMixer.subscribe_recording(mixer,
      id: "recording-output",
      tenant_id: @identity.tenant_id,
      room_id: @identity.room_id,
      incarnation_id: @identity.incarnation_id,
      recording_token: recording_token,
      mode: mode,
      subscriber: self()
    )
  end

  defp frame(source, sequence, timestamp, samples, overrides \\ []) do
    fields =
      @identity
      |> Map.merge(%{
        source_participant_id: source,
        connection_id: "connection-#{source}",
        track_id: "track-#{source}",
        sequence_number: sequence,
        timestamp: timestamp,
        policy_revision: 0,
        sample_rate: 8_000,
        channels: 1,
        payload: encode_samples(samples)
      })
      |> Map.merge(Map.new(overrides))

    struct!(NormalizedFrame, fields)
  end

  defp egress_frame(source, connection_id, samples) do
    %EgressAcceptedFrame{
      tenant_id: @identity.tenant_id,
      room_id: @identity.room_id,
      incarnation_id: @identity.incarnation_id,
      source_participant_id: source,
      connection_id: connection_id,
      sample_rate: 8_000,
      channels: 1,
      payload: encode_samples(samples)
    }
  end

  defp assert_frame({:ok, [%MixedFrame{} = frame]}, recipient, sources, samples, revision) do
    assert frame.recipient_participant_id == recipient
    assert frame.source_participant_ids == sources
    assert frame.policy_revision == revision
    assert decode_samples(frame.payload) == samples
  end

  defp encode_samples(samples) do
    Enum.reduce(samples, <<>>, fn sample, payload ->
      <<payload::binary, sample::little-signed-16>>
    end)
  end

  defp decode_samples(payload) do
    for <<sample::little-signed-16 <- payload>>, do: sample
  end
end
