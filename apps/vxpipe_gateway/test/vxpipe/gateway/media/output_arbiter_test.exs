defmodule Vxpipe.Gateway.Media.OutputArbiterTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Media.{AudioOutputFrame, MixedFrame, OutputSink}
  alias Vxpipe.Gateway.Media.OutputArbiter
  alias Vxpipe.Gateway.TestOpusEncoder
  alias Vxpipe.Gateway.WebRTC.AudioEgress

  test "collects private output readiness while room binding and hold change independently" do
    alias Vxpipe.CallEngine.Readiness.Collector

    {output, native} = start_output()
    assert {:ok, native_resource, :ready} = AudioEgress.readiness(native)
    assert {:ok, resource, :ready} = OutputArbiter.readiness(output)
    assert resource.kind == :private_output
    assert resource.scope == {:participant, "caller"}
    assert resource.binding == "connection"

    assert {:ok, [^resource, ^native_resource] = resources} =
             OutputArbiter.readiness_resources(output)

    collector =
      start_supervised!(
        {Collector,
         owner: self(),
         incarnation_id: "incarnation",
         attempt_id: "output-readiness",
         resources: resources,
         deadline_ms: System.monotonic_time(:millisecond) + 5_000}
      )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000
    assert :ok = OutputSink.hold(output, 1)
    assert {:ok, ^resource, :ready} = OutputArbiter.readiness(output)
    assert :ok = OutputSink.release(output, 1)
    assert {:ok, token} = OutputArbiter.bind_room(output, identity())
    assert {:ok, room, :ready} = OutputArbiter.room_binding_readiness(output, token)
    assert room.kind == :room_output_binding
    assert room.generation == token
    assert {:ok, ^room, :ready} = OutputArbiter.readiness_binding(room)
    assert {:ok, ^resource, :ready} = OutputArbiter.readiness(output)

    assert {:error, :wrong_recipient} =
             OutputArbiter.bind_room(output, %{identity() | participant_id: "other"})

    assert {:ok, ^room, :ready} = OutputArbiter.readiness_binding(room)
    assert {:ok, _new_token} = OutputArbiter.bind_room(output, identity())
    assert {:error, :unavailable} = OutputArbiter.readiness_binding(room)
    assert {:ok, ^resource, :ready} = OutputArbiter.readiness(output)
    assert {:ok, ^native_resource, :ready} = AudioEgress.readiness(native)
    refute_receive {:rtp, _packet}

    assert :ok = stop_supervised({AudioEgress, "connection"})
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :failed}}, 1_000
    assert {:error, :unavailable} = OutputArbiter.readiness(output)
  end

  test "a native output without a readiness adapter cannot become ready" do
    {output, _native} = start_output(__MODULE__)
    assert {:ok, resource, :failed} = OutputArbiter.readiness(output)
    assert resource.kind == :private_output
    assert {:ok, [^resource]} = OutputArbiter.readiness_resources(output)
    refute_receive {:rtp, _packet}
  end

  test "room readiness requires the current arbiter binding, independently of private output" do
    alias Vxpipe.Gateway.Media.RoomAudioEgress

    {output, native} = start_output()
    room = start_room_output(output, [])
    assert :ok = RoomAudioEgress.await_ready(room)
    assert {:ok, _room_resource, :ready} = RoomAudioEgress.readiness(room)
    assert {:ok, resources} = RoomAudioEgress.readiness_resources(room)
    assert Enum.any?(resources, &(&1.kind == :room_output_binding and &1.instance == output))
    assert {:ok, private, :ready} = OutputArbiter.readiness(output)
    assert {:ok, codec, :ready} = AudioEgress.readiness(native)

    assert {:ok, _replacement} = OutputArbiter.bind_room(output, identity())
    assert {:error, :unavailable} = RoomAudioEgress.readiness(room)
    assert {:ok, ^private, :ready} = OutputArbiter.readiness(output)
    assert {:ok, ^codec, :ready} = AudioEgress.readiness(native)
  end

  test "the production room path and direct path share native output delivery" do
    alias Vxpipe.Gateway.Media.RoomAudioEgress

    {output, native} = start_output()
    room = start_room_output(output, [mixed(0)])

    assert :ok = RoomAudioEgress.await_ready(room)
    assert :ok = OutputSink.push(output, direct("opening"))
    assert :ok = OutputSink.finish(output, "opening", self())
    assert_receive {:rtp, %{sequence_number: 0, timestamp: 0, ssrc: ssrc}}
    assert_receive {:pace, ^native, tick}
    send(native, tick)
    assert_receive {:vxpipe_audio_playback, ^output, "opening", {:completed, 20}}
    send(room, {:vxpipe_room_audio_available, self(), "connection:room-output"})
    assert_receive {:rtp, %{sequence_number: 1, timestamp: 960, ssrc: ^ssrc}}
    assert_receive {:pace, ^native, room_tick}
    send(native, room_tick)
  end

  test "private playback follows the current room frame on one encoder and RTP clock" do
    {output, native} = start_output()
    assert {:ok, binding} = OutputArbiter.bind_room(output, identity())
    assert :ok = OutputArbiter.push_room(output, binding, mixed(0))
    assert_receive {:rtp, %{sequence_number: 0, timestamp: 0, ssrc: ssrc}}
    assert_receive {:pace, ^native, tick}

    request = :gen_server.send_request(output, {:vxpipe_audio_output, direct("cue")})
    _ = :sys.get_state(output)
    assert :timeout = :gen_server.wait_response(request, 0)
    refute_receive {:rtp, _}
    send(native, tick)
    assert_receive {:vxpipe_room_output, ^output, ^binding, 0}
    assert {:reply, :ok} = :gen_server.wait_response(request, 1_000)
    assert_receive {:rtp, %{sequence_number: 1, timestamp: 960, ssrc: ^ssrc}}
    assert_receive {:pace, ^native, cue_tick}
    assert :ok = OutputSink.finish(output, "cue", self())
    assert :dropped = OutputArbiter.push_room(output, binding, mixed(960))
    refute_receive {:vxpipe_audio_playback, ^output, "cue", {:completed, _}}
    send(native, cue_tick)
    assert_receive {:vxpipe_audio_playback, ^output, "cue", {:completed, 20}}
    assert :ok = OutputArbiter.push_room(output, binding, mixed(1920))
    assert_receive {:rtp, %{sequence_number: 2, timestamp: 1920, ssrc: ^ssrc}}
  end

  test "hold drains existing output, fences old generations and permits only private playback" do
    {output, native} = start_output()
    assert {:ok, binding} = OutputArbiter.bind_room(output, identity())
    assert :ok = OutputSink.push(output, %{direct("old") | audio_scope: :conversation})
    assert_receive {:pace, ^native, tick}
    request = :gen_server.send_request(output, {:vxpipe_audio_output_hold, 1})
    _ = :sys.get_state(output)
    assert :timeout = :gen_server.wait_response(request, 0)
    assert {:error, :held} = OutputArbiter.push_room(output, binding, mixed(0))
    send(native, tick)
    assert {:reply, :ok} = :gen_server.wait_response(request, 1_000)
    assert {:error, :stale_output_generation} = OutputSink.push(output, direct("old"))
    cue = Map.put(direct("cue"), :output_generation, 1)
    assert :ok = OutputSink.push(output, cue)
    assert_receive {:pace, ^native, cue_tick}
    assert :ok = OutputSink.finish(output, "cue", self())
    assert {:error, :output_not_drained} = OutputSink.release(output, 1)
    assert {:error, :stale_output_generation} = OutputSink.release(output, 0)
    send(native, cue_tick)
    assert_receive {:vxpipe_audio_playback, ^output, "cue", {:completed, 20}}
    assert :ok = OutputSink.release(output, 1)
    assert {:error, :stale_output_generation} = OutputSink.push(output, direct("old"))
    assert {:error, :stale_output_generation} = OutputArbiter.push_room(output, binding, mixed(0))

    assert :ok =
             OutputArbiter.push_room(output, binding, Map.put(mixed(960), :output_generation, 1))
  end

  test "replacing a room binding drains the old frame and rejects its late writes" do
    {output, native} = start_output()
    assert {:ok, old_binding} = OutputArbiter.bind_room(output, identity())
    assert :ok = OutputArbiter.push_room(output, old_binding, mixed(0))
    assert_receive {:pace, ^native, tick}
    request = :gen_server.send_request(output, {:bind_room, identity()})
    _ = :sys.get_state(output)
    assert :timeout = :gen_server.wait_response(request, 0)
    send(native, tick)
    assert {:reply, {:ok, binding}} = :gen_server.wait_response(request, 1_000)
    refute binding == old_binding

    assert {:error, :stale_room_binding} =
             OutputArbiter.push_room(output, old_binding, mixed(960))

    assert :ok = OutputArbiter.push_room(output, binding, mixed(960))
    assert_receive {:rtp, %{sequence_number: 1, timestamp: 960}}
    refute_receive {:vxpipe_room_output, ^output, ^old_binding, _}
  end

  test "room binding during clear waits for the drain instead of failing the connection" do
    {output, native} = start_output()
    assert :ok = OutputSink.push(output, direct("old"))
    assert_receive {:pace, ^native, tick}
    clear = :gen_server.send_request(output, :vxpipe_audio_output_clear)
    binding = :gen_server.send_request(output, {:bind_room, identity()})
    _ = :sys.get_state(output)
    assert :timeout = :gen_server.wait_response(binding, 0)
    send(native, tick)
    assert {:reply, {:ok, 20}} = :gen_server.wait_response(clear, 1_000)
    assert {:reply, {:ok, token}} = :gen_server.wait_response(binding, 1_000)
    assert :ok = OutputArbiter.push_room(output, token, mixed(0))
  end

  test "invalid direct frames cannot strand the shared room output" do
    {output, _native} = start_output()
    assert {:ok, binding} = OutputArbiter.bind_room(output, identity())

    assert {:error, :unsupported_audio} =
             OutputSink.push(output, %{direct("invalid") | sample_rate: 8_000})

    assert :ok = OutputArbiter.push_room(output, binding, mixed(0))
  end

  test "room replacement preserves an already waiting private turn" do
    {output, native} = start_output()
    assert {:ok, old_binding} = OutputArbiter.bind_room(output, identity())
    assert :ok = OutputArbiter.push_room(output, old_binding, mixed(0))
    assert_receive {:pace, ^native, tick}
    private = :gen_server.send_request(output, {:vxpipe_audio_output, direct("opening")})
    binding = :gen_server.send_request(output, {:bind_room, identity()})
    _ = :sys.get_state(output)
    assert :timeout = :gen_server.wait_response(private, 0)
    send(native, tick)
    assert {:reply, {:ok, _}} = :gen_server.wait_response(binding, 1_000)
    assert {:reply, :ok} = :gen_server.wait_response(private, 1_000)
    assert_receive {:vxpipe_audio_playback, ^output, "opening", :started}
  end

  test "a dead direct producer cannot retain ownership of the recipient output" do
    {output, native} = start_output()
    assert {:ok, binding} = OutputArbiter.bind_room(output, identity())
    observer = self()

    producer =
      start_supervised!(
        {Task,
         fn ->
           :ok = OutputSink.push(output, direct("abandoned"))
           send(observer, :producer_started)
           receive do: (:stop -> :ok)
         end}
      )

    assert_receive :producer_started
    assert_receive {:pace, ^native, tick}
    monitor = Process.monitor(producer)
    send(producer, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^producer, :normal}
    _ = :sys.get_state(output)
    send(native, tick)
    _ = :sys.get_state(native)
    _ = :sys.get_state(output)
    assert :ok = OutputArbiter.push_room(output, binding, mixed(0))
  end

  test "WebRTC drain requires the final paced frame to finish" do
    {output, native} = start_output()
    assert :ok = OutputSink.push(output, direct("cue"))
    assert :ok = OutputSink.finish(output, "cue", self())
    assert_receive {:pace, ^native, tick}
    assert {:error, :output_not_drained} = OutputSink.drain(output)
    send(native, tick)
    assert_receive {:vxpipe_audio_playback, ^output, "cue", {:completed, 20}}
    assert :ok = OutputSink.drain(output)
  end

  defp start_room_output(output, frames) do
    alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot}
    alias Vxpipe.Gateway.WebRTC.ConnectionPeerSupervisor

    start_supervised!({ConnectionPeerSupervisor, connection_id: "connection"})
    observer = self()

    store =
      start_supervised!(
        {Agent,
         fn ->
           %{
             observer: observer,
             output_configuration: {:ok, %{mode: :mix_minus}},
             frames: frames,
             snapshot: %Snapshot{
               revision: 0,
               present_participant_ids: MapSet.new(["caller", "agent"]),
               effective: %Effective{
                 audio_routes: :unrestricted,
                 transcript_routes: :unrestricted,
                 record_audio: true,
                 save_transcripts: true
               }
             }
           }
         end}
      )

    assert {:ok, room} =
             ConnectionPeerSupervisor.start_room_audio_egress(
               "connection",
               %{store: store},
               Map.to_list(identity()),
               output,
               engine: Vxpipe.Gateway.TestRoomAudioOutputEngine
             )

    room
  end

  defp start_output(native_adapter \\ AudioEgress) do
    observer = self()

    native =
      start_supervised!(
        {AudioEgress,
         tenant_id: "tenant",
         room_id: "room",
         incarnation_id: "incarnation",
         participant_id: "caller",
         connection_id: "connection",
         peer_connection: self(),
         track_id: "track",
         encoder: {TestOpusEncoder, [observer: self()]},
         send_rtp: fn _, _, packet ->
           send(observer, {:rtp, packet})
           :ok
         end,
         schedule: fn target, message, _ ->
           send(observer, {:pace, target, message})
           make_ref()
         end}
      )

    output =
      start_supervised!(
        {OutputArbiter,
         tenant_id: "tenant",
         room_id: "room",
         incarnation_id: "incarnation",
         participant_id: "caller",
         connection_id: "connection",
         native_output: native,
         native_adapter: native_adapter,
         owner: self()}
      )

    {output, native}
  end

  defp identity,
    do: %{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "caller"
    }

  defp direct(turn) do
    %AudioOutputFrame{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "agent",
      connection_id: "connection",
      command_id: "command",
      correlation_id: turn,
      codec: :linear16,
      sample_rate: 48_000,
      channels: 1,
      byte_order: :little,
      payload: :binary.copy(<<1, 0>>, 960),
      reply_to: self(),
      audio_scope: :private
    }
  end

  defp mixed(timestamp) do
    %MixedFrame{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      subscription_id: "subscription",
      recipient_participant_id: "caller",
      mode: :mix_minus,
      source_participant_ids: ["agent"],
      timestamp: timestamp,
      policy_revision: 0,
      sample_rate: 48_000,
      channels: 1,
      payload: :binary.copy(<<2, 0>>, 960)
    }
  end
end
