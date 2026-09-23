defmodule Vxpipe.Gateway.WebRTC.SourceReceiverTest do
  use ExUnit.Case, async: true

  alias ExRTP.Packet
  alias Vxpipe.Gateway.TestWebRTCSourcePeer
  alias Vxpipe.Gateway.WebRTC.SourceReceiver

  test "queued old RTP retains its receiver epoch after a successor starts" do
    old_epoch = make_ref()
    fresh_epoch = make_ref()
    peer = self()

    old =
      start_supervised!(
        {SourceReceiver, owner: self(), epoch: old_epoch, clock: fn -> 1_000 end},
        id: make_ref()
      )

    :ok = :sys.suspend(old)

    on_exit(fn ->
      try do
        :sys.resume(old)
      catch
        :exit, _ -> :ok
      end
    end)

    old_packet = packet(1)
    send(old, {:ex_webrtc, peer, {:rtp, "microphone", nil, old_packet}})

    fresh =
      start_supervised!(
        {SourceReceiver, owner: self(), epoch: fresh_epoch, clock: fn -> 2_000 end},
        id: make_ref()
      )

    fresh_packet = packet(2)
    send(fresh, {:ex_webrtc, peer, {:rtp, "microphone", nil, fresh_packet}})

    assert_receive {:vxpipe_webrtc_source, ^fresh, ^fresh_epoch, 2_000,
                    {:ex_webrtc, ^peer, {:rtp, "microphone", nil, ^fresh_packet}}}

    :ok = :sys.resume(old)

    assert_receive {:vxpipe_webrtc_source, ^old, ^old_epoch, 1_000,
                    {:ex_webrtc, ^peer, {:rtp, "microphone", nil, ^old_packet}}}
  end

  test "non-media peer notifications retain their original shape" do
    receiver =
      start_supervised!(
        {SourceReceiver, owner: self(), epoch: make_ref(), clock: fn -> 1_000 end},
        id: make_ref()
      )

    message = {:ex_webrtc, self(), {:connection_state_change, :connected}}
    send(receiver, message)
    assert_receive ^message
  end

  test "receiver-owned peer barrier drains old RTP before committing a fresh epoch" do
    old_epoch = make_ref()
    fresh_epoch = make_ref()
    old_packet = packet(1)
    fresh_packet = packet(2)

    receiver =
      start_supervised!(
        {SourceReceiver, owner: self(), epoch: old_epoch, clock: fn -> 1_000 end},
        id: make_ref()
      )

    peer =
      start_supervised!(
        {TestWebRTCSourcePeer,
         owner: receiver,
         barrier_events: [
           {:connection_state_change, :connected},
           {:rtp, "microphone", nil, old_packet}
         ]},
        id: make_ref()
      )

    assert :ok = SourceReceiver.bind_peer(receiver, peer, 1_000)
    assert :ok = SourceReceiver.cutover(receiver, old_epoch, fresh_epoch, 1_000)
    assert_receive {:ex_webrtc, ^peer, {:connection_state_change, :connected}}

    assert_receive {:vxpipe_webrtc_source, ^receiver, ^old_epoch, 1_000,
                    {:ex_webrtc, ^peer, {:rtp, "microphone", nil, ^old_packet}}}

    assert {:error, :stale_epoch} =
             SourceReceiver.cutover(receiver, old_epoch, make_ref(), 1_000)

    assert 1 == TestWebRTCSourcePeer.barrier_count(peer)
    assert :ok = TestWebRTCSourcePeer.emit(peer, {:rtp, "microphone", nil, fresh_packet})

    assert_receive {:vxpipe_webrtc_source, ^receiver, ^fresh_epoch, 1_000,
                    {:ex_webrtc, ^peer, {:rtp, "microphone", nil, ^fresh_packet}}}
  end

  test "peer barrier failure leaves the receiver on its old epoch" do
    old_epoch = make_ref()

    receiver =
      start_supervised!(
        {SourceReceiver, owner: self(), epoch: old_epoch, clock: fn -> 1_000 end},
        id: make_ref()
      )

    peer =
      start_supervised!(
        {TestWebRTCSourcePeer, owner: receiver, barrier_reply: {:error, :invalid_state}},
        id: make_ref()
      )

    assert :ok = SourceReceiver.bind_peer(receiver, peer, 1_000)

    assert {:error, :invalid_state} =
             SourceReceiver.cutover(receiver, old_epoch, make_ref(), 1_000)

    packet = packet(1)
    assert :ok = TestWebRTCSourcePeer.emit(peer, {:rtp, "microphone", nil, packet})

    assert_receive {:vxpipe_webrtc_source, ^receiver, ^old_epoch, 1_000,
                    {:ex_webrtc, ^peer, {:rtp, "microphone", nil, ^packet}}}
  end

  test "a dead or different peer cannot authorize cutover" do
    old_epoch = make_ref()

    receiver =
      start_supervised!(
        {SourceReceiver, owner: self(), epoch: old_epoch, clock: fn -> 1_000 end},
        id: make_ref()
      )

    peer_id = make_ref()
    peer = start_supervised!({TestWebRTCSourcePeer, owner: receiver}, id: peer_id)
    other_peer = start_supervised!({TestWebRTCSourcePeer, owner: receiver}, id: make_ref())

    assert {:error, :unbound_peer} =
             SourceReceiver.cutover(receiver, old_epoch, make_ref(), 1_000)

    assert :ok = SourceReceiver.bind_peer(receiver, peer, 1_000)
    assert {:error, :peer_mismatch} = SourceReceiver.bind_peer(receiver, other_peer, 1_000)

    monitor = Process.monitor(peer)
    assert :ok = stop_supervised(peer_id)
    assert_receive {:DOWN, ^monitor, :process, ^peer, _reason}

    assert {:error, :unavailable} =
             SourceReceiver.cutover(receiver, old_epoch, make_ref(), 1_000)

    packet = packet(1)
    send(receiver, {:ex_webrtc, peer, {:rtp, "microphone", nil, packet}})

    assert_receive {:vxpipe_webrtc_source, ^receiver, ^old_epoch, 1_000,
                    {:ex_webrtc, ^peer, {:rtp, "microphone", nil, ^packet}}}
  end

  test "a timed-out queued cutover cannot commit after the receiver resumes" do
    old_epoch = make_ref()

    receiver =
      start_supervised!(
        {SourceReceiver, owner: self(), epoch: old_epoch, clock: fn -> 1_000 end},
        id: make_ref()
      )

    peer = start_supervised!({TestWebRTCSourcePeer, owner: receiver}, id: make_ref())
    assert :ok = SourceReceiver.bind_peer(receiver, peer, 1_000)
    :ok = :sys.suspend(receiver)

    on_exit(fn ->
      try do
        :sys.resume(receiver)
      catch
        :exit, _ -> :ok
      end
    end)

    assert {:error, :unavailable} =
             SourceReceiver.cutover(receiver, old_epoch, make_ref(), 10)

    :ok = :sys.resume(receiver)
    _ = :sys.get_state(receiver)
    packet = packet(1)
    assert :ok = TestWebRTCSourcePeer.emit(peer, {:rtp, "microphone", nil, packet})

    assert_receive {:vxpipe_webrtc_source, ^receiver, ^old_epoch, 1_000,
                    {:ex_webrtc, ^peer, {:rtp, "microphone", nil, ^packet}}}
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
