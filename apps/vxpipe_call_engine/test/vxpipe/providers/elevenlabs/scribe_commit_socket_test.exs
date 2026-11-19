defmodule Vxpipe.Providers.ElevenLabs.ScribeCommitSocketTest do
  use ExUnit.Case, async: false
  @moduletag :integration
  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff, SettingsSupervisor}
  alias Vxpipe.CallEngine.Speech.Socket
  alias Vxpipe.CallEngine.TestSpeechWireServer
  alias Vxpipe.Providers.ElevenLabs.{Scribe, ScribeSocket}

  test "timed commits send exactly the existing frame and revoked observation cannot block sending" do
    parent = self()

    start_supervised!(
      {SettingsSupervisor,
       name: __MODULE__.Settings,
       projection: __MODULE__.Projection,
       reader: __MODULE__.Reader,
       loader: fn ->
         send(parent, :loaded)
         {:ok, %{enabled: true, revision: 1}}
       end}
    )

    assert_receive :loaded
    _ = :sys.get_state(__MODULE__.Reader)
    _ = :sys.get_state(__MODULE__.Projection)
    {:ok, handoff} = CaptureHandoff.new(self(), projection: __MODULE__.Projection)
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
