defmodule Vxpipe.Providers.Google.STTSocketTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.TestSpeechWireServer
  alias Vxpipe.Providers.Google.STTSocket

  test "a deferred replacement connects without blocking its owner and accepts setup afterward" do
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
               transport_options: [],
               deferred: true
             ]
           ]}
      })

    assert_receive {:vxpipe_socket_connected, ^socket}, 1_000
    assert :ok = STTSocket.send_control(socket, ~s({"setup":{}}))
    assert_receive {:speech_wire_frame, _, :text, ~s({"setup":{}})}, 1_000
  end
end
