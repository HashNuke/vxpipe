defmodule Vxpipe.CallEngine.Integration.SpeechSocketPrivacyTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Providers.Deepgram.{
    Flux,
    STTSocket,
    FluxTextToSpeech,
    TTSSocket
  }

  alias Vxpipe.Providers.Deepgram.Flux.Session, as: FluxSession
  alias Vxpipe.Providers.Deepgram.FluxTextToSpeech.Session, as: FluxTTSSession
  alias Vxpipe.CallEngine.Speech.{Audio, CapabilityTree, Event, Session}
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
    socket = start_socket(STTSocket, context.endpoint)
    assert_receive {:speech_wire_authorization, ["Token " <> @secret]}
    assert_receive {:speech_wire_connected, peer}
    assert :ok = STTSocket.send_audio(socket, <<1, 2, 3>>)
    assert_receive {:speech_wire_frame, ^peer, :binary, <<1, 2, 3>>}

    send(peer, {:send, [text: "transcript", binary: "binary-transcript", ping: "probe"]})
    assert_receive {:vxpipe_stt_transport, ^socket, {:message, "transcript"}}
    assert_receive {:vxpipe_stt_transport, ^socket, {:message, "binary-transcript"}}
    assert_receive {:speech_wire_frame, ^peer, :pong, "probe"}

    monitor = Process.monitor(socket)
    assert :ok = STTSocket.close(socket)
    assert_receive {:speech_wire_frame, ^peer, :text, ~s({"type":"CloseStream"})}
    assert_receive {:DOWN, ^monitor, :process, ^socket, _reason}
    assert_private_telemetry(socket)
  end

  test "TTS authenticates only on the wire and acknowledges output before continuing", context do
    socket = start_socket(TTSSocket, context.endpoint)
    assert_receive {:speech_wire_authorization, ["Token " <> @secret]}
    assert_receive {:speech_wire_connected, peer}
    assert :ok = TTSSocket.send_control(socket, "speak")
    assert_receive {:speech_wire_frame, ^peer, :text, "speak"}

    send(peer, {:send, [binary: <<4, 5>>, text: "completed"]})
    assert_receive {:vxpipe_tts_transport, ^socket, {:audio, reference, <<4, 5>>}}
    refute_receive {:vxpipe_tts_transport, ^socket, {:control, "completed"}}, 20
    send(socket, {:vxpipe_tts_audio_result, self(), reference, :ok})
    assert_receive {:vxpipe_tts_transport, ^socket, {:control, "completed"}}

    monitor = Process.monitor(socket)
    assert :ok = TTSSocket.close(socket)
    assert_receive {:speech_wire_frame, ^peer, :text, ~s({"type":"Close"})}
    assert_receive {:DOWN, ^monitor, :process, ^socket, _reason}
    assert_private_telemetry(socket)
  end

  test "TTS close remains responsive while output acknowledgement is pending", context do
    socket = start_socket(TTSSocket, context.endpoint)
    assert_receive {:speech_wire_connected, peer}
    send(peer, {:send, [binary: <<4, 5>>]})
    assert_receive {:vxpipe_tts_transport, ^socket, {:audio, _reference, <<4, 5>>}}

    monitor = Process.monitor(socket)
    assert :ok = TTSSocket.close(socket)
    assert_receive {:speech_wire_frame, ^peer, :text, ~s({"type":"Close"})}
    assert_receive {:DOWN, ^monitor, :process, ^socket, :normal}
  end

  test "TTS ignores another owner's acknowledgement and closes on output failure", context do
    socket = start_socket(TTSSocket, context.endpoint)
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
    socket = start_socket(STTSocket, context.endpoint)
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
        start_supervised(socket_spec(STTSocket, TestSpeechWireServer.endpoint(server), []))
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
        socket_spec(STTSocket, TestSpeechWireServer.endpoint(server), receive_timeout: 40)
      )

    assert {:error, {:connection_unavailable, _child}} = result
    assert System.monotonic_time(:millisecond) - started < 1_000
    assert_receive {:speech_wire_stalled, peer}
    send(peer, :release)
  end

  test "an initial provider frame received with the HTTP upgrade is delivered" do
    start_supervised!({Vxpipe.CallEngine.TestSpeechUpgradeServer, owner: self()})
    assert_receive {:speech_upgrade_endpoint, endpoint}
    socket = start_socket(STTSocket, endpoint)
    assert_receive {:vxpipe_stt_transport, ^socket, {:message, "initial"}}
    assert :ok = STTSocket.close(socket)
  end

  test "native STT maps a coalesced Connected frame and drops a duplicate turn sequence" do
    connected =
      JSON.encode!(%{"type" => "Connected", "request_id" => "request-1", "sequence_id" => 0})

    server =
      start_supervised!(
        {Vxpipe.CallEngine.TestSpeechUpgradeServer, owner: self(), frames: [text: connected]}
      )

    assert_receive {:speech_upgrade_endpoint, endpoint}

    assert {:ok, config} =
             Flux.new(
               api_key: @secret,
               model: "flux-general-en",
               encoding: :opus,
               sample_rate: 48_000
             )

    config = %{config | endpoint: endpoint}

    scope =
      start_supervised!(Supervisor.child_spec({CapabilityTree, owner: self()}, id: make_ref()))
      |> CapabilityTree.scope()

    assert {:ok, session, :starting} =
             Session.start(scope,
               provider: FluxSession,
               options: [
                 model: config.model,
                 encoding: config.encoding,
                 sample_rate: config.sample_rate
               ],
               private: [config: config, wire_options: []]
             )

    assert_receive {:speech_upgrade_connected, ^server}, 1_000
    assert %Event{kind: :ready, provider_request_id: "request-1"} = next_event(session)

    send(
      server,
      {:send,
       [
         text: turn_message("StartOfTurn", 1, "hello"),
         text: turn_message("Update", 1, "FORBIDDEN"),
         text: turn_message("Update", 2, "hello there"),
         text: turn_message("EndOfTurn", 3, "hello there", "model")
       ]}
    )

    assert %Event{kind: :speech_started} = next_event(session)
    assert %Event{kind: :transcript, text: "hello"} = next_event(session)
    assert %Event{kind: :transcript, text: "hello there"} = next_event(session)
    assert %Event{kind: :turn_ended, text: "hello there"} = next_event(session)
    refute_received {:vxpipe_speech, %Event{text: "FORBIDDEN"}}
    assert :ok = Session.close(session)
  end

  test "native TTS maps wire audio without requiring speech-start and completes after credit",
       context do
    assert {:ok, config} =
             FluxTextToSpeech.new(
               api_key: @secret,
               model: "flux-haley-en",
               encoding: :linear16,
               sample_rate: 16_000
             )

    config = %{config | endpoint: context.endpoint}

    scope =
      start_supervised!(Supervisor.child_spec({CapabilityTree, owner: self()}, id: make_ref()))
      |> CapabilityTree.scope()

    assert {:ok, session, :starting} =
             Session.start(scope,
               provider: FluxTTSSession,
               options: [
                 model: config.model,
                 encoding: config.encoding,
                 sample_rate: config.sample_rate
               ],
               private: [config: config, wire_options: []]
             )

    assert_receive {:speech_wire_authorization, ["Token " <> @secret]}
    assert_receive {:speech_wire_connected, peer}

    send(
      peer,
      {:send, [text: JSON.encode!(%{"type" => "Connected", "request_id" => "connection-tts"})]}
    )

    assert %Event{
             kind: :ready,
             provider_request_id: "connection-tts",
             readiness: :provider_acknowledged
           } = next_event(session)

    assert {:ok, %{ref: request}} = Session.speak(session, "Hello")

    assert_receive {:speech_wire_frame, ^peer, :text, speak}
    assert JSON.decode!(speak) == %{"type" => "Speak", "text" => "Hello"}
    assert_receive {:speech_wire_frame, ^peer, :text, flush}
    assert JSON.decode!(flush) == %{"type" => "Flush"}

    assert %Event{kind: :input_submitted, request_ref: ^request} = next_event(session)

    audio = <<1::little-signed-16, 2::little-signed-16>>

    send(
      peer,
      {:send,
       [
         binary: audio,
         text:
           JSON.encode!(%{
             "type" => "SpeechMetadata",
             "speech_id" => "dg_sp_native_tts"
           })
       ]}
    )

    assert_receive {:vxpipe_speech_audio,
                    %Audio{session: ^session, request_ref: ^request, payload: ^audio} = envelope},
                   1_000

    assert :ok = Session.validate_audio(session, envelope)
    refute_receive {:vxpipe_speech, %Event{kind: :completed}}, 20
    assert :ok = Session.ack_audio(session, envelope)

    assert %Event{
             kind: :completed,
             request_ref: ^request,
             provider_request_id: "dg_sp_native_tts"
           } = next_event(session)

    assert {:ok, completed_ticket} = Session.fence_output(session, request)
    assert {:ok, _playback} = Session.cancel(session, completed_ticket, 0)

    assert {:ok, %{ref: cancelled_request}} = Session.speak(session, "Stop")
    assert_receive {:speech_wire_frame, ^peer, :text, _speak}
    assert_receive {:speech_wire_frame, ^peer, :text, _flush}
    assert %Event{kind: :input_submitted, request_ref: ^cancelled_request} = next_event(session)

    cancelled_audio = <<3::little-signed-16, 4::little-signed-16>>

    send(
      peer,
      {:send,
       [
         binary: cancelled_audio,
         text:
           JSON.encode!(%{
             "type" => "SpeechMetadata",
             "speech_id" => "dg_sp_cancelled_tts"
           })
       ]}
    )

    assert_receive {:vxpipe_speech_audio,
                    %Audio{
                      session: ^session,
                      request_ref: ^cancelled_request,
                      payload: ^cancelled_audio
                    } = fenced_envelope},
                   1_000

    assert :ok = Session.validate_audio(session, fenced_envelope)
    assert {:ok, cancellation} = Session.fence_output(session, cancelled_request)
    assert {:ok, _playback} = Session.cancel(session, cancellation, 0)

    assert %Event{
             kind: :cancelled,
             request_ref: ^cancelled_request,
             provider_request_id: "dg_sp_cancelled_tts"
           } = next_event(session)
  end

  test "an unacknowledged output closes at the fixed output deadline", context do
    socket = start_socket(TTSSocket, context.endpoint)
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
    socket = start_socket(TTSSocket, endpoint)
    assert_receive {:vxpipe_tts_transport, ^socket, {:audio, _reference, <<4, 5>>}}
    refute inspect(:sys.get_state(socket), limit: :infinity) =~ @secret
    refute inspect(:sys.get_status(socket), limit: :infinity) =~ @secret
    assert :ok = TTSSocket.close(socket)
  end

  test "TTS sends its configured keepalive ping", context do
    socket = start_socket(TTSSocket, context.endpoint, keepalive_interval: 20)
    assert_receive {:speech_wire_connected, peer}
    assert_receive {:speech_wire_frame, ^peer, :ping, ""}
    assert :ok = TTSSocket.close(socket)
  end

  def observe(_event, _measurements, metadata, owner) do
    send(owner, {:speech_transport_telemetry, self(), metadata})
  end

  defp next_event(session) do
    assert_receive {:vxpipe_speech, %Event{session: ^session} = event}, 1_000
    assert :ok = Session.ack(session, event)
    event
  end

  defp turn_message(event, sequence, transcript, trigger \\ nil) do
    message = %{
      "type" => "TurnInfo",
      "request_id" => "request-1",
      "sequence_id" => sequence,
      "event" => event,
      "turn_index" => 0,
      "audio_window_start" => 0.0,
      "audio_window_end" => 1.0,
      "transcript" => transcript,
      "words" => [],
      "end_of_turn_confidence" => 0.8
    }

    message = if trigger, do: Map.put(message, "trigger", trigger), else: message
    JSON.encode!(message)
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
