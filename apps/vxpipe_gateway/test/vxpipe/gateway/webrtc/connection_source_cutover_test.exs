defmodule Vxpipe.Gateway.WebRTC.ConnectionSourceCutoverTest do
  use ExUnit.Case, async: true

  alias ExRTP.Packet
  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.Gateway.TestWebRTCSourcePeer
  alias Vxpipe.Gateway.WebRTC.{Connection, SourceReceiver}

  test "only the owning room can hold and arm the exact attached WebRTC source" do
    {state, peer, receiver} = connection()
    token = make_ref()
    hold = scope(state, token)

    assert {:reply, {:error, :unauthorized}, ^state} =
             Connection.handle_call({:vxpipe_sts_source_hold, hold}, {peer, make_ref()}, state)

    assert {:reply, {:error, :unauthorized}, ^state} =
             Connection.handle_call(
               {:vxpipe_sts_source_hold, %{hold | attachment: make_ref()}},
               {self(), make_ref()},
               state
             )

    old_packet = packet(1)
    assert :ok = TestWebRTCSourcePeer.emit(peer, {:rtp, "microphone", nil, old_packet})

    assert {:reply, {:ok, receipt}, held} =
             Connection.handle_call({:vxpipe_sts_source_hold, hold}, {self(), make_ref()}, state)

    assert %{held?: true, token: ^token} = held.source_gate
    assert receipt.old_epoch == state.source_epoch
    assert receipt.held_epoch == held.source_epoch
    assert receipt.receiver == receiver

    assert_receive {:vxpipe_webrtc_source, ^receiver, old_epoch, _,
                    {:ex_webrtc, ^peer, {:rtp, "microphone", nil, ^old_packet}}}

    assert old_epoch == state.source_epoch
    held_packet = packet(2)
    assert :ok = TestWebRTCSourcePeer.emit(peer, {:rtp, "microphone", nil, held_packet})

    assert_receive {:vxpipe_webrtc_source, ^receiver, held_epoch, _,
                    {:ex_webrtc, ^peer, {:rtp, "microphone", nil, ^held_packet}}}

    assert held_epoch == receipt.held_epoch

    active_epoch = make_ref()
    arm = Map.merge(scope(held, token), %{receipt: receipt, active_epoch: active_epoch})

    assert {:reply, {:error, :unauthorized}, ^held} =
             Connection.handle_call({:vxpipe_sts_source_arm, arm}, {peer, make_ref()}, held)

    assert {:reply, {:error, :stale_source}, ^held} =
             Connection.handle_call(
               {:vxpipe_sts_source_arm, %{arm | token: make_ref()}},
               {self(), make_ref()},
               held
             )

    assert {:reply, {:error, :stale_source}, ^held} =
             Connection.handle_call(
               {:vxpipe_sts_source_arm, %{arm | active_epoch: receipt.old_epoch}},
               {self(), make_ref()},
               held
             )

    assert {:reply, {:ok, ^active_epoch}, active} =
             Connection.handle_call({:vxpipe_sts_source_arm, arm}, {self(), make_ref()}, held)

    assert %{held?: false} = active.source_gate
    assert active.source_epoch == active_epoch
    active_packet = packet(3)
    assert :ok = TestWebRTCSourcePeer.emit(peer, {:rtp, "microphone", nil, active_packet})

    assert_receive {:vxpipe_webrtc_source, ^receiver, ^active_epoch, _,
                    {:ex_webrtc, ^peer, {:rtp, "microphone", nil, ^active_packet}}}

    assert {:reply, {:error, :stale_source}, ^active} =
             Connection.handle_call({:vxpipe_sts_source_arm, arm}, {self(), make_ref()}, active)

    assert {:reply, {:error, :stale_source}, ^active} =
             Connection.handle_call(
               {:vxpipe_sts_source_hold, scope(active, token)},
               {self(), make_ref()},
               active
             )
  end

  test "transfer hold prevents an STS source arm" do
    {state, _peer, _receiver} = connection()
    token = make_ref()

    assert {:reply, {:ok, receipt}, held} =
             Connection.handle_call(
               {:vxpipe_sts_source_hold, scope(state, token)},
               {self(), make_ref()},
               state
             )

    arm =
      Map.merge(scope(held, token), %{receipt: receipt, active_epoch: make_ref()})

    transfer_held = Map.put(held, :handoff_gate, %{held?: true})

    assert {:reply, {:error, :transfer_held}, still_held} =
             Connection.handle_call(
               {:vxpipe_sts_source_arm, arm},
               {self(), make_ref()},
               transfer_held
             )

    assert %{held?: true} = still_held.source_gate
    replay_state = %{still_held | handoff_gate: nil}

    assert {:reply, {:error, :stale_source}, ^replay_state} =
             Connection.handle_call(
               {:vxpipe_sts_source_arm, arm},
               {self(), make_ref()},
               replay_state
             )
  end

  test "an expired arm is terminal even if the same receipt gets a new deadline" do
    {state, _peer, _receiver} = connection()
    token = make_ref()

    assert {:reply, {:ok, receipt}, held} =
             Connection.handle_call(
               {:vxpipe_sts_source_hold, scope(state, token)},
               {self(), make_ref()},
               state
             )

    arm = Map.merge(scope(held, token), %{receipt: receipt, active_epoch: make_ref()})
    expired = %{arm | deadline_ms: System.monotonic_time(:millisecond) - 1}

    assert {:reply, {:error, :deadline_elapsed}, expired_state} =
             Connection.handle_call({:vxpipe_sts_source_arm, expired}, {self(), make_ref()}, held)

    assert %{held?: true} = expired_state.source_gate

    assert {:reply, {:error, :stale_source}, ^expired_state} =
             Connection.handle_call(
               {:vxpipe_sts_source_arm, arm},
               {self(), make_ref()},
               expired_state
             )
  end

  test "a delayed peer reply leaves Connection held and cannot commit a late epoch" do
    {state, peer, receiver} = connection()
    :ok = :sys.suspend(peer)

    on_exit(fn ->
      try do
        :sys.resume(peer)
      catch
        :exit, _reason -> :ok
      end
    end)

    token = make_ref()
    delayed = %{scope(state, token) | deadline_ms: System.monotonic_time(:millisecond) + 1_000}

    assert {:reply, {:error, :source_unavailable}, uncertain} =
             Connection.handle_call(
               {:vxpipe_sts_source_hold, delayed},
               {self(), make_ref()},
               state
             )

    assert %{held?: true, status: :uncertain} = uncertain.source_gate
    assert uncertain.source_epoch == state.source_epoch
    :ok = :sys.resume(peer)
    _ = :sys.get_state(receiver)

    late_packet = packet(4)
    assert :ok = TestWebRTCSourcePeer.emit(peer, {:rtp, "microphone", nil, late_packet})

    assert_receive {:vxpipe_webrtc_source, ^receiver, old_epoch, _,
                    {:ex_webrtc, ^peer, {:rtp, "microphone", nil, ^late_packet}}}

    assert old_epoch == state.source_epoch

    assert {:reply, {:error, :stale_source}, ^uncertain} =
             Connection.handle_call(
               {:vxpipe_sts_source_arm,
                Map.merge(scope(uncertain, token), %{
                  receipt: %{},
                  active_epoch: make_ref()
                })},
               {self(), make_ref()},
               uncertain
             )
  end

  test "held-period RTP keeps its held epoch across the separate arm barrier" do
    {state, peer, receiver} = connection()
    token = make_ref()

    assert {:reply, {:ok, receipt}, held} =
             Connection.handle_call(
               {:vxpipe_sts_source_hold, scope(state, token)},
               {self(), make_ref()},
               state
             )

    :ok = :sys.suspend(receiver)

    on_exit(fn ->
      try do
        :sys.resume(receiver)
      catch
        :exit, _reason -> :ok
      end
    end)

    held_packet = packet(5)
    assert :ok = TestWebRTCSourcePeer.emit(peer, {:rtp, "microphone", nil, held_packet})

    arm = Map.merge(scope(held, token), %{receipt: receipt, active_epoch: make_ref()})
    supervisor = start_supervised!(Task.Supervisor)
    test_pid = self()

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        send(test_pid, :arm_requested)
        Connection.handle_call({:vxpipe_sts_source_arm, arm}, {test_pid, make_ref()}, held)
      end)

    assert_receive :arm_requested
    :ok = :sys.resume(receiver)

    assert {:reply, {:ok, active_epoch}, active} = Task.await(task, 1_000)

    assert_receive {:vxpipe_webrtc_source, ^receiver, held_epoch, _,
                    {:ex_webrtc, ^peer, {:rtp, "microphone", nil, ^held_packet}}}

    assert held_epoch == receipt.held_epoch
    assert active.source_epoch == active_epoch
  end

  test "receiver loss before arm cannot open the source or reuse its receipt" do
    {state, _peer, receiver} = connection()
    token = make_ref()

    assert {:reply, {:ok, receipt}, held} =
             Connection.handle_call(
               {:vxpipe_sts_source_hold, scope(state, token)},
               {self(), make_ref()},
               state
             )

    monitor = Process.monitor(receiver)
    Process.exit(receiver, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^receiver, :killed}

    arm = Map.merge(scope(held, token), %{receipt: receipt, active_epoch: make_ref()})

    assert {:reply, {:error, :source_unavailable}, uncertain} =
             Connection.handle_call({:vxpipe_sts_source_arm, arm}, {self(), make_ref()}, held)

    assert %{held?: true, status: :uncertain} = uncertain.source_gate

    assert {:reply, {:error, :stale_source}, ^uncertain} =
             Connection.handle_call(
               {:vxpipe_sts_source_arm, arm},
               {self(), make_ref()},
               uncertain
             )
  end

  defp connection do
    old_epoch = make_ref()

    receiver =
      start_supervised!(
        {SourceReceiver, owner: self(), epoch: old_epoch},
        id: make_ref()
      )

    peer = start_supervised!({TestWebRTCSourcePeer, owner: receiver}, id: make_ref())
    assert :ok = SourceReceiver.bind_peer(receiver, peer, 1_000)

    attachment = %ConnectionAttachment{
      room_authority: self(),
      room_monitor: make_ref(),
      media_ingress: nil
    }

    {%{
       attachment: attachment,
       source_receiver: receiver,
       source_epoch: old_epoch,
       peer_connection: peer,
       handoff_gate: nil,
       source_gate: nil
     }, peer, receiver}
  end

  defp scope(state, token) do
    %{
      attachment: state.attachment.room_monitor,
      token: token,
      deadline_ms: System.monotonic_time(:millisecond) + 7_000
    }
  end

  defp packet(sequence_number) do
    %Packet{
      payload_type: 111,
      sequence_number: sequence_number,
      timestamp: sequence_number * 960,
      ssrc: 123,
      payload: <<1, 2, 3>>
    }
  end
end
