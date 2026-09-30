defmodule Vxpipe.Providers.Cartesia.STTSocketTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.TestSpeechWireServer
  alias Vxpipe.Providers.Cartesia.STTSocket

  test "owned socket sends raw binary audio and a drain command without closing locally" do
    server = start_supervised!({TestSpeechWireServer, owner: self()})

    socket =
      start_supervised!(%{
        id: make_ref(),
        start:
          {STTSocket, :start_link,
           [
             [
               owner: self(),
               connection: %{url: TestSpeechWireServer.endpoint(server), headers: []},
               transport_options: []
             ]
           ]},
        restart: :temporary
      })

    assert_receive {:vxpipe_socket_connected, ^socket}, 1_000
    monitor = Process.monitor(socket)
    assert :ok = STTSocket.send_audio(socket, <<1, 0, 2, 0>>)
    assert_receive {:speech_wire_frame, _, :binary, <<1, 0, 2, 0>>}, 1_000
    assert :ok = STTSocket.finish_input(socket)
    assert_receive {:speech_wire_frame, _, :text, payload}, 1_000
    assert JSON.decode!(payload) == %{"type" => "close"}
    _ = :sys.get_state(socket)
    refute_received {:DOWN, ^monitor, :process, ^socket, _reason}
    assert {:error, :invalid_audio} = STTSocket.send_audio(socket, <<1>>)
  end
end
