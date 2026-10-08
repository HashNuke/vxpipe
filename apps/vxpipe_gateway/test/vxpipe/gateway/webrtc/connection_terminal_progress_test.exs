defmodule Vxpipe.Gateway.WebRTC.ConnectionTerminalProgressTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.Gateway.WebRTC.Connection

  test "a held transfer's room shutdown preserves terminal progress until peer disconnect" do
    room_monitor = make_ref()
    handoff_monitor = make_ref()
    admission_monitor = make_ref()
    peer_monitor = make_ref()
    channel = make_ref()

    state = %{
      peer_connection: self(),
      rtvi_channel_ref: channel,
      attachment: %ConnectionAttachment{
        admission: :main,
        room_monitor: room_monitor,
        media_ingress: nil
      },
      room_monitor: room_monitor,
      handoff_gate: %{monitor: handoff_monitor, held?: true},
      admission_monitor: admission_monitor,
      peer_monitor: peer_monitor,
      peer_left_timeout_token: nil
    }

    progress = %{destination: "support", phase: :failed, blockers: [], reason: :timeout}

    assert {:noreply, ^state} =
             Connection.handle_info({:vxpipe_transfer_progress, "attempt", progress}, state)

    assert_receive {:"$gen_cast", {:send_data, ^channel, :string, payload}}

    assert %{
             "type" => "server-message",
             "data" => %{"t" => "vxpipe.transfer", "d" => %{"phase" => "failed"}}
           } = JSON.decode!(payload)

    assert {:noreply, closing} =
             Connection.handle_info(
               {:DOWN, handoff_monitor, :process, self(), :handoff_release_failed},
               state
             )

    assert closing.handoff_gate.held?
    token = closing.peer_left_timeout_token
    assert is_reference(token)

    assert_receive {:"$gen_cast", {:send_data, ^channel, :string, peer_left}}
    assert %{"message" => %{"type" => "peerLeft"}} = JSON.decode!(peer_left)

    for monitor <- [room_monitor, admission_monitor, handoff_monitor] do
      assert {:noreply, ^closing} =
               Connection.handle_info({:DOWN, monitor, :process, self(), :shutdown}, closing)
    end

    refute_received {:"$gen_cast", {:send_data, ^channel, :string, _duplicate}}

    assert {:stop, :shutdown, ^closing} =
             Connection.handle_info({:vxpipe_peer_left_timeout, token}, closing)

    assert {:stop, :shutdown, ^closing} =
             Connection.handle_info({:DOWN, peer_monitor, :process, self(), :normal}, closing)
  end
end
