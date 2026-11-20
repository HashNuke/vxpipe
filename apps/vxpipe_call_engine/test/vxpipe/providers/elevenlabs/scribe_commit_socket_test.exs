defmodule Vxpipe.Providers.ElevenLabs.ScribeCommitSocketTest do
  use ExUnit.Case, async: false

  setup do
    Vxpipe.CallEngine.TestCallSettings.start!(__MODULE__)
    :ok
  end

  @moduletag :integration
  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff}
  alias Vxpipe.CallEngine.Speech.Socket
  alias Vxpipe.CallEngine.TestSpeechWireServer
  alias Vxpipe.Providers.ElevenLabs.{Scribe, ScribeSocket}

  test "timed commits send exactly the existing frame and revoked observation cannot block sending" do
    {:ok, handoff} =
      CaptureHandoff.new(self(), settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))

    server = start_supervised!({TestSpeechWireServer, owner: self()})

    socket =
      start_supervised!(%{
        id: make_ref(),
        restart: :temporary,
        start:
          {ScribeSocket, :start_link,
           [
             [
               owner: self(),
               commit_strategy: :vad,
               diagnostic_handoff: handoff,
               connection: %{url: TestSpeechWireServer.endpoint(server), headers: []},
               transport_options: []
             ]
           ]}
      })

    assert_receive {:vxpipe_socket_connected, ^socket}, 1_000
    assert_receive {:speech_wire_connected, server_socket}, 1_000
    before = System.monotonic_time(:microsecond)
    assert {:ok, {token, sent_at}} = ScribeSocket.commit_with_receipt(socket)
    after_send = System.monotonic_time(:microsecond)
    assert token == handoff.token
    assert before <= sent_at and sent_at <= after_send
    assert_receive {:speech_wire_frame, ^server_socket, :text, payload}, 1_000
    assert payload == Scribe.commit()
    refute_received {:speech_wire_frame, ^server_socket, :text, _}

    CaptureHandoff.close(handoff)
    assert {:ok, nil} = ScribeSocket.commit_with_receipt(socket)
    assert_receive {:speech_wire_frame, ^server_socket, :text, ^payload}, 1_000
    refute_received {:speech_wire_frame, ^server_socket, :text, _}
    Socket.retire(socket)
    _ = :sys.get_state(socket)
    assert {:error, :retiring} = ScribeSocket.commit_with_receipt(socket)
    refute_received {:speech_wire_frame, ^server_socket, :text, _}
  end

  test "socket receipts snapshot only successfully sent audio samples" do
    {:ok, handoff} =
      CaptureHandoff.new(self(), settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))

    server = start_supervised!({TestSpeechWireServer, owner: self()})

    socket =
      start_supervised!(%{
        id: make_ref(),
        start:
          {ScribeSocket, :start_link,
           [
             [
               owner: self(),
               commit_strategy: :vad,
               diagnostic_handoff: handoff,
               connection: %{url: TestSpeechWireServer.endpoint(server), headers: []},
               transport_options: []
             ]
           ]}
      })

    assert_receive {:vxpipe_socket_connected, ^socket}, 1_000
    assert_receive {:speech_wire_connected, peer}, 1_000
    assert :ok = ScribeSocket.send_audio(socket, :binary.copy(<<0, 0>>, 320))
    assert_receive {:speech_wire_frame, ^peer, :text, _}, 1_000
    payload = JSON.encode!(%{"message_type" => "partial_transcript", "text" => "synthetic"})
    send(peer, {:send, [{:text, payload}]})
    token = handoff.token

    assert_receive {:vxpipe_scribe_transport, ^socket,
                    {:event, {:partial, "synthetic"}, {^token, _, 320}}},
                   1_000

    retiring = %{:sys.get_state(socket) | retiring?: true}
    assert retiring.callback_state.sent_samples == 320

    assert {:reply, {:error, :retiring}, ^retiring} =
             Socket.handle_call(
               {:send, {:text, "not sent"}, {:audio_samples, 320}},
               {self(), make_ref()},
               retiring
             )
  end

  test "existing uninstrumented evidence wrapper can still send audio without the optional callback" do
    server = start_supervised!({TestSpeechWireServer, owner: self()})

    socket =
      start_supervised!(%{
        id: make_ref(),
        start:
          {Vxpipe.CallEngine.ScribeEvidenceSocket, :start_link,
           [
             [
               owner: self(),
               connection: %{url: TestSpeechWireServer.endpoint(server), headers: []},
               transport_options: [observer: self()]
             ]
           ]}
      })

    assert_receive {:vxpipe_socket_connected, ^socket}, 1_000
    assert_receive {:speech_wire_connected, peer}, 1_000

    assert :ok =
             Vxpipe.CallEngine.ScribeEvidenceSocket.send_audio(
               socket,
               :binary.copy(<<0, 0>>, 320)
             )

    assert_receive {:speech_wire_frame, ^peer, :text, payload}, 1_000
    assert JSON.decode!(payload)["audio_base_64"] == Base.encode64(:binary.copy(<<0, 0>>, 320))
  end

  test "timed send before connection readiness returns the existing error without a receipt" do
    state = %Socket{connection: nil}

    assert {:reply, {:error, :not_ready}, ^state} =
             Socket.handle_call(
               {:send_with_receipt, {:text, Scribe.commit()}},
               {self(), make_ref()},
               state
             )
  end
end
