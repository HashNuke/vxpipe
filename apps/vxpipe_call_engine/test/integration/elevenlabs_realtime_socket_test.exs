defmodule Vxpipe.CallEngine.Integration.ElevenLabsRealtimeSocketTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Vxpipe.CallEngine.TestSpeechUpgradeServer
  alias Vxpipe.Providers.ElevenLabs.RealtimeSocket

  test "a stalled session receives only one wire frame until it acknowledges admission" do
    peer =
      start_supervised!(
        Supervisor.child_spec({TestSpeechUpgradeServer, owner: self(), frames: []},
          restart: :temporary
        )
      )

    assert_receive {:speech_upgrade_endpoint, endpoint}

    socket =
      start_supervised!(%{
        id: RealtimeSocket,
        start:
          {RealtimeSocket, :start_link,
           [[owner: self(), connection: %{url: endpoint, headers: []}, transport_options: []]]},
        restart: :temporary
      })

    assert_receive {:vxpipe_socket_connected, ^socket}, 1_000

    assert :ok =
             GenServer.call(
               peer,
               {:send, for(n <- 1..32, do: {:text, JSON.encode!(%{"type" => "test", "n" => n})})}
             )

    assert_receive {:elevenlabs_realtime, ^socket, credit, first}, 1_000
    assert JSON.decode!(first)["n"] == 1
    _ = :sys.get_state(socket)
    refute_received {:elevenlabs_realtime, ^socket, _, _}
    RealtimeSocket.ack(socket, credit)
    assert_receive {:elevenlabs_realtime, ^socket, _credit, second}, 1_000
    assert JSON.decode!(second)["n"] == 2
    assert :ok = RealtimeSocket.close(socket)
  end
end
