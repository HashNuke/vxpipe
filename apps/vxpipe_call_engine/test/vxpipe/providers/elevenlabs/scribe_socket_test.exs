defmodule Vxpipe.Providers.ElevenLabs.ScribeSocketTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Vxpipe.CallEngine.TestSpeechWireServer
  alias Vxpipe.Providers.ElevenLabs.ScribeSocket

  test "idle keepalive sends an empty noncommitting protocol message without speech events" do
    server = start_supervised!({TestSpeechWireServer, owner: self()})

    socket =
      start_supervised!(%{
        id: make_ref(),
        start:
          {ScribeSocket, :start_link,
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
    send(socket, :keepalive)

    assert_receive {:speech_wire_frame, _, :text, payload}, 1_000

    assert JSON.decode!(payload) == %{
             "message_type" => "input_audio_chunk",
             "audio_base_64" => "",
             "commit" => false,
             "sample_rate" => 16_000
           }

    assert :sys.get_state(socket).keepalive_interval == 10_000
    refute_received {:vxpipe_scribe_transport, ^socket, _event}
    assert {:error, :invalid_audio} = ScribeSocket.send_audio(socket, "")
  end

  test "decodes segments and removes private provider error text before notifying its owner" do
    observer = self()
    state = %{owner: observer}

    assert {:ok, ^state} =
             ScribeSocket.handle_frame(
               {:text,
                JSON.encode!(%{"message_type" => "committed_transcript", "text" => "Hello"})},
               state
             )

    assert_received {:vxpipe_scribe_transport, ^observer, {:event, {:segment, "Hello"}}}

    assert {:ok, ^state} =
             ScribeSocket.handle_frame(
               {:text,
                JSON.encode!(%{
                  "message_type" => "auth_error",
                  "error" => "synthetic-private-detail"
                })},
               state
             )

    assert_received {:vxpipe_scribe_transport, ^observer, {:closed, :provider_failure}}
    refute_received {:vxpipe_scribe_transport, ^observer, {:message, _private_payload}}
  end

  test "an owned socket sends base64 PCM and a commit without claiming drain completion" do
    server = start_supervised!({TestSpeechWireServer, owner: self()})

    socket =
      start_supervised!(%{
        id: make_ref(),
        start:
          {ScribeSocket, :start_link,
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
    assert :ok = ScribeSocket.send_audio(socket, <<1, 0, 2, 0>>)
    assert_receive {:speech_wire_frame, _, :text, audio}, 1_000
    assert JSON.decode!(audio)["audio_base_64"] == Base.encode64(<<1, 0, 2, 0>>)
    assert JSON.decode!(audio)["commit"] == false
    assert :ok = ScribeSocket.commit(socket)
    assert_receive {:speech_wire_frame, _, :text, commit}, 1_000
    assert JSON.decode!(commit)["commit"] == true
    _ = :sys.get_state(socket)
    refute_received {:DOWN, ^monitor, :process, ^socket, _reason}
    assert {:error, :invalid_audio} = ScribeSocket.send_audio(socket, <<1>>)
  end
end
