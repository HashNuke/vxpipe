defmodule Vxpipe.Console.LiveTelephonyPeerSocketTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Console.Test.LiveTelephonyPeerSocket
  alias Vxpipe.Gateway.Telephony.MediaBinding

  setup do
    start_supervised!({Registry, keys: :unique, name: LiveTelephonyPeerSocket.Registry})
    leg = start_supervised!({Agent, fn -> nil end})

    binding = %MediaBinding{
      provider: :telnyx,
      service_id: "service",
      ingress_key: "ingress",
      tenant_id: "tenant",
      call_id: "call",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "human",
      provider_connection_id: "application",
      provider_call_control_id: "private-control",
      provider_call_leg_id: "provider-leg",
      provider_call_session_id: "session",
      client_state_leg_id: "leg",
      leg: leg
    }

    %{binding: binding}
  end

  test "socket observation retains the exact binding behind tenant/call/participant lookup",
       %{binding: binding} do
    assert {:ok, state} = LiveTelephonyPeerSocket.init(%{binding: binding})
    assert state.module == Vxpipe.Providers.Telnyx.TelephonyMediaSocket
    assert {:ok, ^binding} = LiveTelephonyPeerSocket.binding("tenant", "call", "human")

    for identity <- [
          {"foreign", "call", "human"},
          {"tenant", "foreign", "human"},
          {"tenant", "call", "foreign"}
        ] do
      assert {:error, :peer_not_connected} =
               apply(LiveTelephonyPeerSocket, :binding, Tuple.to_list(identity))
    end
  end

  test "a duplicate socket cannot replace the bound peer", %{binding: binding} do
    assert {:ok, _state} = LiveTelephonyPeerSocket.init(%{binding: binding})
    replacement = %{binding | provider_call_control_id: "other-private-control"}

    assert {:stop, :peer_already_connected, _state} =
             LiveTelephonyPeerSocket.init(%{binding: replacement})

    assert {:ok, ^binding} = LiveTelephonyPeerSocket.binding("tenant", "call", "human")
  end
end
