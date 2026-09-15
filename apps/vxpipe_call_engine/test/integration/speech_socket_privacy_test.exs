defmodule Vxpipe.CallEngine.Integration.SpeechSocketPrivacyTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Provider.Deepgram.{FluxSocket, FluxTextToSpeechSocket}
  alias Vxpipe.CallEngine.TestSpeechWireServer

  @moduletag :integration
  @secret "synthetic-speech-wire-secret"
  @events [
    [:websockex, :connected],
    [:websockex, :disconnected],
    [:websockex, :terminate],
    [:websockex, :frame, :sent],
    [:websockex, :frame, :received]
  ]

  setup do
    handler = {__MODULE__, make_ref()}
    :ok = :telemetry.attach_many(handler, @events, &__MODULE__.observe/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)
    server = start_supervised!({TestSpeechWireServer, owner: self()})
    %{endpoint: TestSpeechWireServer.endpoint(server)}
  end

  test "STT authenticates only on the wire and preserves frames, ping and close", context do
    socket = start_socket(FluxSocket, context.endpoint)
    assert_receive {:speech_wire_authorization, ["Token " <> @secret]}
    assert_receive {:speech_wire_connected, peer}
    assert :ok = FluxSocket.send_audio(socket, <<1, 2, 3>>)
    assert_receive {:speech_wire_frame, ^peer, :binary, <<1, 2, 3>>}

    send(peer, {:send, [text: "transcript", binary: "binary-transcript", ping: "probe"]})
    assert_receive {:vxpipe_stt_transport, ^socket, {:message, "transcript"}}
    assert_receive {:vxpipe_stt_transport, ^socket, {:message, "binary-transcript"}}
    assert_receive {:speech_wire_frame, ^peer, :pong, "probe"}

    monitor = Process.monitor(socket)
    assert :ok = FluxSocket.close(socket)
    assert_receive {:speech_wire_frame, ^peer, :text, ~s({"type":"CloseStream"})}
    assert_receive {:DOWN, ^monitor, :process, ^socket, _reason}
    assert_private_telemetry(socket)
  end

  test "TTS authenticates only on the wire and acknowledges output before continuing", context do
    socket = start_socket(FluxTextToSpeechSocket, context.endpoint)
    assert_receive {:speech_wire_authorization, ["Token " <> @secret]}
    assert_receive {:speech_wire_connected, peer}
    assert :ok = FluxTextToSpeechSocket.send_control(socket, "speak")
    assert_receive {:speech_wire_frame, ^peer, :text, "speak"}

    send(peer, {:send, [binary: <<4, 5>>, text: "completed"]})
    assert_receive {:vxpipe_tts_transport, ^socket, {:audio, reference, <<4, 5>>}}
    refute_receive {:vxpipe_tts_transport, ^socket, {:control, "completed"}}, 20
    send(socket, {:vxpipe_tts_audio_result, self(), reference, :ok})
    assert_receive {:vxpipe_tts_transport, ^socket, {:control, "completed"}}

    monitor = Process.monitor(socket)
    assert :ok = FluxTextToSpeechSocket.close(socket)
    assert_receive {:speech_wire_frame, ^peer, :text, ~s({"type":"Close"})}
    assert_receive {:DOWN, ^monitor, :process, ^socket, _reason}
    assert_private_telemetry(socket)
  end

  test "TTS close remains responsive while output acknowledgement is pending", context do
    socket = start_socket(FluxTextToSpeechSocket, context.endpoint)
    assert_receive {:speech_wire_connected, peer}
    send(peer, {:send, [binary: <<4, 5>>]})
    assert_receive {:vxpipe_tts_transport, ^socket, {:audio, _reference, <<4, 5>>}}

    monitor = Process.monitor(socket)
    assert :ok = FluxTextToSpeechSocket.close(socket)
    assert_receive {:speech_wire_frame, ^peer, :text, ~s({"type":"Close"})}
    assert_receive {:DOWN, ^monitor, :process, ^socket, :normal}
  end

  test "TTS ignores another owner's acknowledgement and closes on output failure", context do
    socket = start_socket(FluxTextToSpeechSocket, context.endpoint)
    assert_receive {:speech_wire_connected, peer}
    send(peer, {:send, [binary: <<4, 5>>, text: "completed"]})
    assert_receive {:vxpipe_tts_transport, ^socket, {:audio, reference, <<4, 5>>}}
    send(socket, {:vxpipe_tts_audio_result, peer, reference, :ok})
    refute_receive {:vxpipe_tts_transport, ^socket, {:control, "completed"}}, 20

    monitor = Process.monitor(socket)

    send(
      socket,
      {:vxpipe_tts_audio_result, self(), reference, {:error, "synthetic-rejected-secret"}}
    )

    assert_receive {:vxpipe_tts_transport, ^socket, {:closed, :connection_lost}}
    assert_receive {:DOWN, ^monitor, :process, ^socket, :normal}
    refute_receive {:vxpipe_tts_transport, ^socket, {:control, "completed"}}, 20
  end

  test "provider close reports one safe failure without reconnecting", context do
    socket = start_socket(FluxSocket, context.endpoint)
    assert_receive {:speech_wire_connected, peer}
    monitor = Process.monitor(socket)
    send(peer, :close)
    assert_receive {:vxpipe_stt_transport, ^socket, {:closed, :connection_lost}}
    assert_receive {:DOWN, ^monitor, :process, ^socket, :normal}
    refute_receive {:speech_wire_connected, _peer}, 20
    assert_private_telemetry(socket)
  end

  test "rejected upgrades expose no provider details" do
    server = start_supervised!({TestSpeechWireServer, owner: self(), response: :reject})

    {result, log} =
      ExUnit.CaptureLog.with_log(fn ->
        start_supervised(socket_spec(FluxSocket, TestSpeechWireServer.endpoint(server), []))
      end)

    assert {:error, {:connection_unavailable, _child}} = result
    refute inspect(result, limit: :infinity) =~ "synthetic-rejected-secret"
    refute log =~ @secret
    refute log =~ "synthetic-rejected-secret"
  end

  test "stalled upgrade uses the configured receive deadline" do
    server = start_supervised!({TestSpeechWireServer, owner: self(), response: :stall})
    started = System.monotonic_time(:millisecond)

    result =
      start_supervised(
        socket_spec(FluxSocket, TestSpeechWireServer.endpoint(server), receive_timeout: 40)
      )

    assert {:error, {:connection_unavailable, _child}} = result
    assert System.monotonic_time(:millisecond) - started < 1_000
    assert_receive {:speech_wire_stalled, peer}
    send(peer, :release)
  end

  test "an initial provider frame received with the HTTP upgrade is delivered" do
    start_supervised!({Vxpipe.CallEngine.TestSpeechUpgradeServer, owner: self()})
    assert_receive {:speech_upgrade_endpoint, endpoint}
    socket = start_socket(FluxSocket, endpoint)
    assert_receive {:vxpipe_stt_transport, ^socket, {:message, "initial"}}
    assert :ok = FluxSocket.close(socket)
  end

  test "an unacknowledged output closes at the fixed output deadline", context do
    socket = start_socket(FluxTextToSpeechSocket, context.endpoint)
    assert_receive {:speech_wire_connected, peer}
    send(peer, {:send, [binary: <<4, 5>>]})
    assert_receive {:vxpipe_tts_transport, ^socket, {:audio, _reference, <<4, 5>>}}
    monitor = Process.monitor(socket)
    assert_receive {:vxpipe_tts_transport, ^socket, {:closed, :connection_lost}}, 16_000
    assert_receive {:DOWN, ^monitor, :process, ^socket, :normal}
  end

  test "routine state inspection excludes pending provider payloads" do
    start_supervised!(
      {Vxpipe.CallEngine.TestSpeechUpgradeServer,
       owner: self(), frames: [binary: <<4, 5>>, text: @secret]}
    )

    assert_receive {:speech_upgrade_endpoint, endpoint}
    socket = start_socket(FluxTextToSpeechSocket, endpoint)
    assert_receive {:vxpipe_tts_transport, ^socket, {:audio, _reference, <<4, 5>>}}
    refute inspect(:sys.get_state(socket), limit: :infinity) =~ @secret
    refute inspect(:sys.get_status(socket), limit: :infinity) =~ @secret
    assert :ok = FluxTextToSpeechSocket.close(socket)
  end

  test "TTS sends its configured keepalive ping", context do
    socket = start_socket(FluxTextToSpeechSocket, context.endpoint, keepalive_interval: 20)
    assert_receive {:speech_wire_connected, peer}
    assert_receive {:speech_wire_frame, ^peer, :ping, ""}
    assert :ok = FluxTextToSpeechSocket.close(socket)
  end

  def observe(_event, _measurements, metadata, owner) do
    send(owner, {:speech_transport_telemetry, self(), metadata})
  end

  defp start_socket(module, endpoint, options \\ []) do
    start_supervised!(socket_spec(module, endpoint, options))
  end

  defp socket_spec(module, endpoint, options) do
    %{
      id: {module, make_ref()},
      start:
        {module, :start_link,
         [
           [
             owner: self(),
             connection: %{url: endpoint, headers: [{"Authorization", "Token " <> @secret}]},
             transport_options: options
           ]
         ]},
      restart: :temporary
    }
  end

  defp assert_private_telemetry(socket) do
    receive do
      {:speech_transport_telemetry, ^socket, metadata} ->
        refute :erlang.term_to_binary(metadata) =~ @secret
        assert_private_telemetry(socket)
    after
      0 -> :ok
    end
  end
end
