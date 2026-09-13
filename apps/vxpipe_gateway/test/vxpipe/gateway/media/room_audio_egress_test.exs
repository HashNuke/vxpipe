defmodule Vxpipe.Gateway.Media.RoomAudioEgressTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Media.MixedFrame
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot}
  alias Vxpipe.Gateway.Media.RoomAudioEgress
  alias Vxpipe.Gateway.WebRTC.ConnectionPeerSupervisor

  test "readiness requires both the output pipeline and its current mixer subscription" do
    connection_id = unique_id("readiness-output")
    start_supervised!({ConnectionPeerSupervisor, connection_id: connection_id})
    attachment = attachment({:ok, %{mode: :mix_minus}}, snapshot(4), [])
    assert {:ok, egress} = start_egress(connection_id, attachment)
    assert_receive {:test_room_audio_output_pipeline_started, pipeline_id, _pipeline, ^egress}
    assert {:ok, _pending, :preparing} = RoomAudioEgress.readiness(egress)
    send(egress, {:vxpipe_room_audio_output_ready, pipeline_id})
    assert {:ok, resource, :ready} = RoomAudioEgress.readiness(egress)
    assert resource.scope == {:participant, "part-human"}
    assert resource.kind == :room_audio_egress
    assert resource.binding == connection_id
    assert {:ok, [^resource, subscription]} = RoomAudioEgress.readiness_resources(egress)
    assert subscription.kind == :audio_subscription

    unrelated = put_in(snapshot(5).effective.transcript_routes, %{})
    assert :ok = Vxpipe.CallEngine.MediaPolicy.Enforcer.apply(egress, unrelated, 1_000)
    assert {:ok, ^resource, :ready} = RoomAudioEgress.readiness(egress)
    Agent.update(attachment.store, &Map.put(&1, :subscription_ready?, false))
    assert {:ok, ^resource, :preparing} = RoomAudioEgress.readiness(egress)
    refute_receive {:test_room_audio_output_pipeline_stopped, _id, _pipeline}

    for invalid <- [
          %{subscription | kind: :recording_subscription},
          %{subscription | scope: {:participant, "someone-else"}},
          %{subscription | binding: "another-output"},
          %{subscription | generation: nil}
        ] do
      Agent.update(attachment.store, &Map.put(&1, :readiness_resource, invalid))
      assert {:ok, _resource, :failed} = RoomAudioEgress.readiness(egress)
    end
  end

  test "does not start a mixer egress for a direct-output attachment" do
    connection_id = unique_id("conn-direct")
    start_supervised!({ConnectionPeerSupervisor, connection_id: connection_id})
    attachment = attachment(:disabled, snapshot(4), [])

    assert {:ok, nil} =
             start_egress(connection_id, attachment)

    refute_receive {:test_room_audio_output_pipeline_started, _id, _pipeline, _owner}
    refute_receive {:test_room_audio_output_subscribed, _id, _subscriber}
  end

  test "stops a launched output pipeline when mixer subscription fails" do
    connection_id = unique_id("conn-subscribe-failure")
    start_supervised!({ConnectionPeerSupervisor, connection_id: connection_id})
    attachment = attachment({:ok, %{mode: :mix_minus}}, snapshot(4), [])
    Agent.update(attachment.store, &Map.put(&1, :subscribe_result, {:error, :mixer_unavailable}))

    assert {:error, :mixer_unavailable} = start_egress(connection_id, attachment)

    assert_receive {:test_room_audio_output_pipeline_started, pipeline_id, pipeline, _owner}
    assert_receive {:test_room_audio_output_pipeline_stopped, ^pipeline_id, ^pipeline}
  end

  test "starts an authorized full-mix egress for a silent monitor" do
    connection_id = unique_id("conn-monitor")
    start_supervised!({ConnectionPeerSupervisor, connection_id: connection_id})
    attachment = attachment({:ok, %{mode: :full_mix}}, snapshot(4), [])

    assert {:ok, egress} = start_egress(connection_id, attachment)

    assert_receive {:test_room_audio_output_pipeline_started, _pipeline_id, _pipeline, ^egress}
    assert_receive {:test_room_audio_output_subscribed, _subscription_id, ^egress}
  end

  test "keeps at most one mixer frame in flight until WebRTC delivery is acknowledged" do
    first = frame(0, 4)
    second = frame(960, 4)
    {egress, pipeline_id, subscription_id} = start_enabled_egress([first, second], 4)

    send(egress, {:vxpipe_room_audio_output_ready, pipeline_id})
    send(egress, {:vxpipe_room_audio_available, self(), subscription_id})

    assert_receive {:test_room_audio_output_take, ^subscription_id, 1}
    assert_receive {:test_room_audio_output_pipeline_push, ^pipeline_id, ^first}

    send(egress, {:vxpipe_room_audio_available, self(), subscription_id})
    refute_receive {:test_room_audio_output_take, ^subscription_id, 1}, 50
    refute_receive {:test_room_audio_output_pipeline_push, ^pipeline_id, ^second}, 50

    send(egress, {:vxpipe_room_audio_output_sent, pipeline_id, 0})

    assert_receive {:test_room_audio_output_take, ^subscription_id, 1}
    assert_receive {:test_room_audio_output_pipeline_push, ^pipeline_id, ^second}
  end

  test "preserves playback and queued audio across unrelated policy revisions" do
    first = frame(0, 4)
    second = frame(960, 4)
    {egress, pipeline_id, subscription_id} = start_enabled_egress([first, second], 4)
    send(egress, {:vxpipe_room_audio_output_ready, pipeline_id})
    send(egress, {:vxpipe_room_audio_available, self(), subscription_id})
    assert_receive {:test_room_audio_output_pipeline_push, ^pipeline_id, ^first}

    joined = %{
      snapshot(5)
      | present_participant_ids: MapSet.new(["part-human", "part-other", "support"])
    }

    assert :ok = Vxpipe.CallEngine.MediaPolicy.Enforcer.apply(egress, joined, 500)
    transcript_only = put_in(snapshot(6).effective.transcript_routes, %{})
    assert :ok = Vxpipe.CallEngine.MediaPolicy.Enforcer.apply(egress, transcript_only, 500)
    refute_receive {:test_room_audio_output_pipeline_stopped, _, _}
    refute_receive {:test_remote_playback_cleared, _}

    send(egress, {:vxpipe_room_audio_available, self(), subscription_id})
    send(egress, {:vxpipe_room_audio_output_sent, pipeline_id, 0})
    assert_receive {:test_room_audio_output_pipeline_push, ^pipeline_id, ^second}
  end

  test "replaces and drains through a clean output pipeline for changed audio permissions" do
    old_frame = frame(0, 4)
    new_frame = frame(960, 5)
    {egress, old_pipeline_id, subscription_id} = start_enabled_egress([old_frame, new_frame], 4)

    send(egress, {:vxpipe_room_audio_output_ready, old_pipeline_id})
    send(egress, {:vxpipe_room_audio_available, self(), subscription_id})
    assert_receive {:test_room_audio_output_pipeline_push, ^old_pipeline_id, ^old_frame}

    changed =
      put_in(snapshot(5).effective.audio_routes, %{"part-other" => MapSet.new(["part-human"])})

    policy_update =
      Task.async(fn -> GenServer.call(egress, {:vxpipe_apply_media_policy, changed}) end)

    assert_receive {:test_room_audio_output_pipeline_stopped, ^old_pipeline_id, _pipeline}
    assert_receive {:test_remote_playback_cleared, pipeline_options}
    assert pipeline_options[:test_observer] == self()

    assert_receive {:test_room_audio_output_pipeline_started, new_pipeline_id, _pipeline, ^egress}

    refute new_pipeline_id == old_pipeline_id
    assert Task.yield(policy_update, 0) == nil

    send(egress, {:vxpipe_room_audio_output_sent, old_pipeline_id, 0})
    send(egress, {:vxpipe_room_audio_available, self(), subscription_id})
    refute_receive {:test_room_audio_output_pipeline_push, ^new_pipeline_id, ^new_frame}, 50

    send(egress, {:vxpipe_room_audio_output_ready, new_pipeline_id})
    assert Task.await(policy_update) == :ok
    assert_receive {:test_room_audio_output_pipeline_push, ^new_pipeline_id, ^new_frame}
  end

  test "ends the connection boundary when its output pipeline becomes unavailable" do
    {egress, pipeline_id, _subscription_id} = start_enabled_egress([], 4)
    monitor = Process.monitor(egress)

    send(egress, {:vxpipe_room_audio_output_unavailable, pipeline_id, :transport_closed})

    assert_receive {:vxpipe_connection_unavailable, {:room_audio_output, :transport_closed}}
    assert_receive {:DOWN, ^monitor, :process, ^egress, :room_audio_output_unavailable}
  end

  defp start_enabled_egress(frames, revision) do
    connection_id = unique_id("conn-mix-minus")
    start_supervised!({ConnectionPeerSupervisor, connection_id: connection_id})
    attachment = attachment({:ok, %{mode: :mix_minus}}, snapshot(revision), frames)

    assert {:ok, egress} = start_egress(connection_id, attachment)

    assert_receive {:test_room_audio_output_pipeline_started, pipeline_id, _pipeline, ^egress}
    assert_receive {:test_room_audio_output_subscribed, subscription_id, ^egress}
    {egress, pipeline_id, subscription_id}
  end

  defp start_egress(connection_id, attachment) do
    ConnectionPeerSupervisor.start_room_audio_egress(
      connection_id,
      attachment,
      [
        tenant_id: "tenant-demo",
        room_id: "room-demo",
        incarnation_id: "rinc-demo",
        participant_id: "part-human"
      ],
      self(),
      engine: Vxpipe.Gateway.TestRoomAudioOutputEngine,
      pipeline: Vxpipe.Gateway.TestRoomAudioOutputPipeline,
      playback_clearer: Vxpipe.Gateway.TestPlaybackClearer,
      pipeline_supervisor: Vxpipe.Gateway.TestRoomAudioOutputPipelineSupervisor,
      pipeline_options: [test_observer: self()]
    )
  end

  defp attachment(output_configuration, snapshot, frames) do
    observer = self()

    store =
      start_supervised!(
        {Agent,
         fn ->
           %{
             observer: observer,
             output_configuration: output_configuration,
             snapshot: snapshot,
             frames: frames
           }
         end}
      )

    %{store: store}
  end

  defp snapshot(revision) do
    %Snapshot{
      revision: revision,
      present_participant_ids: MapSet.new(["part-human", "part-other"]),
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: :unrestricted,
        record_audio: true,
        save_transcripts: true
      }
    }
  end

  defp frame(timestamp, revision) do
    %MixedFrame{
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      subscription_id: "ignored-by-fixture",
      recipient_participant_id: "part-human",
      mode: :mix_minus,
      source_participant_ids: ["part-other"],
      timestamp: timestamp,
      policy_revision: revision,
      sample_rate: 48_000,
      channels: 1,
      payload: :binary.copy(<<100::little-signed-16>>, 960)
    }
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
