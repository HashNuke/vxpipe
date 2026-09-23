defmodule Vxpipe.Gateway.WebRTC.SourceReceiverTest do
  use ExUnit.Case, async: true

  alias ExRTP.Packet
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
