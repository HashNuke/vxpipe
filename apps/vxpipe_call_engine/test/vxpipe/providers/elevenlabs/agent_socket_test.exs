defmodule Vxpipe.Providers.ElevenLabs.AgentSocketTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.TestSpeechWireServer
  alias Vxpipe.Providers.ElevenLabs.AgentSocket

  test "delivers native response identity to its owner without retaining unrelated private fields" do
    observer = self()
    state = %{owner: observer}

    assert {:ok, ^state} =
             AgentSocket.handle_frame(
               {:text,
                JSON.encode!(%{
                  "type" => "agent_response",
                  "agent_response_event" => %{
                    "event_id" => 5,
                    "response_id" => "response-synthetic",
                    "agent_response" => "Hello"
                  },
                  "private" => "synthetic-private-detail"
                })},
               state
             )

    assert_received {:vxpipe_elevenlabs_agent_transport, ^observer,
                     {:event, {:agent_response, 5, "response-synthetic", "Hello"}}}

    refute_received {:vxpipe_elevenlabs_agent_transport, ^observer, {:message, _raw}}
  end

  test "reduces malformed payloads and disconnect reasons to safe failures" do
    observer = self()
    state = %{owner: observer}
    assert {:ok, ^state} = AgentSocket.handle_frame({:text, "synthetic-private-detail"}, state)
    assert_received {:vxpipe_elevenlabs_agent_transport, ^observer, {:closed, :invalid_message}}
    assert {:ok, ^state} = AgentSocket.handle_disconnect("synthetic-private-detail", state)
    assert_received {:vxpipe_elevenlabs_agent_transport, ^observer, {:closed, :connection_lost}}
  end

  test "identifies a rejected native message kind without returning its private payload" do
    observer = self()
    state = %{owner: observer}

    assert {:ok, ^state} =
             AgentSocket.handle_frame(
               {:text,
                JSON.encode!(%{
                  "type" => "agent_response",
                  "private" => "synthetic-private-detail"
                })},
               state
             )

    assert_received {:vxpipe_elevenlabs_agent_transport, ^observer,
                     {:closed, {:invalid_message, :agent_response}}}
  end

  @tag :integration
  test "owned transport sends initiation, PCM, pong, context and tool result as distinct frames" do
    server = start_supervised!({TestSpeechWireServer, owner: self()})

    socket =
      start_supervised!(%{
        id: make_ref(),
        start:
          {AgentSocket, :start_link,
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
    assert :ok = AgentSocket.initiate(socket)
    assert_frame(%{"type" => "conversation_initiation_client_data"})
    assert :ok = AgentSocket.send_audio(socket, <<1, 0>>)
    assert_frame(%{"user_audio_chunk" => Base.encode64(<<1, 0>>)})
    assert :ok = AgentSocket.pong(socket, 6)
    assert_frame(%{"type" => "pong", "event_id" => 6})
    assert :ok = AgentSocket.contextual_update(socket, "Room instruction")
    assert_frame(%{"type" => "contextual_update", "text" => "Room instruction"})
    assert :ok = AgentSocket.user_message(socket, "Hello")
    assert_frame(%{"type" => "user_message", "text" => "Hello"})
    assert :ok = AgentSocket.tool_result(socket, "tool-synthetic", "sunny", false)

    assert_frame(%{
      "type" => "client_tool_result",
      "tool_call_id" => "tool-synthetic",
      "result" => "sunny",
      "is_error" => false
    })

    assert {:error, :invalid_audio} = AgentSocket.send_audio(socket, <<1>>)
  end

  defp assert_frame(expected) do
    assert_receive {:speech_wire_frame, _, :text, payload}, 1_000
    assert JSON.decode!(payload) == expected
  end
end
