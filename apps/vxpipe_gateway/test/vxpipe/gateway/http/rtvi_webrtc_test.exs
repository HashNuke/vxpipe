defmodule Vxpipe.Gateway.HTTP.RTVIWebRTCTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias ExRTP.Packet
  alias ExWebRTC.{DataChannel, ICECandidate, MediaStreamTrack, PeerConnection, SessionDescription}
  alias Membrane.Opus.Encoder.Native, as: OpusEncoder
  alias Vxpipe.CallEngine.Provider.Deepgram.{Flux, FluxTextToSpeech}
  alias Vxpipe.CallEngine.{TestEchoModelProvider, TestTurnCall}
  alias Vxpipe.CallEngine.TestSpeechToTextTransport
  alias Vxpipe.CallEngine.TestTextToSpeechTransport
  alias Vxpipe.Gateway.HTTP.Endpoint

  @moduletag capture_log: true

  @endpoint_options Endpoint.init(
                      cors: [],
                      room_creation: [
                        enabled: true,
                        agent: :deterministic_text,
                        principal: [
                          tenant_id: "tenant-development",
                          actor_id: "actor-samples",
                          scopes: ["rooms:create", "rooms:join"]
                        ]
                      ]
                    )

  test "connects one admitted participant and completes RTVI readiness" do
    room_id = "room-webrtc-#{System.unique_integer([:positive, :monotonic])}"
    session_id = create_room_session(room_id)

    client = start_supervised!({PeerConnection, []})
    :ok = PeerConnection.controlling_process(client, self())

    {:ok, %DataChannel{ref: client_channel}} =
      PeerConnection.create_data_channel(client, "chat", ordered: true)

    {:ok, _transceiver} = PeerConnection.add_transceiver(client, :audio, direction: :sendrecv)
    {:ok, offer} = PeerConnection.create_offer(client)
    :ok = PeerConnection.set_local_description(client, offer)

    offer_body =
      JSON.encode!(%{
        "sdp" => offer.sdp,
        "type" => "offer",
        "pc_id" => nil,
        "restart_pc" => false,
        "requestData" => %{"session_id" => session_id}
      })

    offer_conn =
      :post
      |> conn("/api/rtvi/offer", offer_body)
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(@endpoint_options)

    assert offer_conn.status == 200

    assert %{"pc_id" => connection_id, "sdp" => answer_sdp, "type" => "answer"} =
             JSON.decode!(offer_conn.resp_body)

    assert "conn_" <> _ = connection_id

    replay_conn =
      :post
      |> conn("/api/rtvi/offer", offer_body)
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(@endpoint_options)

    assert replay_conn.status == 409

    assert %{"error" => %{"code" => "session_already_claimed"}} =
             JSON.decode!(replay_conn.resp_body)

    :ok =
      PeerConnection.set_remote_description(
        client,
        %SessionDescription{type: :answer, sdp: answer_sdp}
      )

    assert_receive {:ex_webrtc, ^client, {:ice_candidate, candidate}}, 5_000
    patch_candidate(connection_id, candidate)

    assert_receive {:ex_webrtc, ^client, {:connection_state_change, :connected}}, 5_000

    assert_receive {:ex_webrtc, ^client, {:data_channel_state_change, ^client_channel, :open}},
                   5_000

    :ok =
      PeerConnection.send_data(
        client,
        client_channel,
        JSON.encode!(%{
          "type" => "signalling",
          "message" => %{"type" => "trackStatus", "receiver_index" => 0, "enabled" => true}
        })
      )

    :ok =
      PeerConnection.send_data(
        client,
        client_channel,
        JSON.encode!(%{
          "id" => "client-ready-1",
          "label" => "rtvi-ai",
          "type" => "client-ready",
          "data" => %{
            "version" => "2.1.0",
            "about" => %{"library" => "@pipecat-ai/client-js", "library_version" => "1.13.0"}
          }
        })
      )

    assert_receive {:ex_webrtc, ^client, {:data, ^client_channel, reply}}, 5_000

    assert %{
             "id" => "client-ready-1",
             "label" => "rtvi-ai",
             "type" => "bot-ready",
             "data" => %{"version" => "2.1.0"}
           } = JSON.decode!(reply)

    :ok =
      PeerConnection.send_data(
        client,
        client_channel,
        JSON.encode!(%{
          "id" => "client-text-1",
          "label" => "rtvi-ai",
          "type" => "send-text",
          "data" => %{
            "content" => "hello",
            "options" => %{"run_immediately" => true, "audio_response" => true}
          }
        })
      )

    assert_receive {:ex_webrtc, ^client, {:data, ^client_channel, user_started}}, 5_000

    assert %{
             "id" => "evt_" <> _,
             "label" => "rtvi-ai",
             "type" => "user-started-speaking",
             "data" => nil
           } = JSON.decode!(user_started)

    assert_receive {:ex_webrtc, ^client, {:data, ^client_channel, user_stopped}}, 5_000

    assert %{
             "id" => "evt_" <> _,
             "label" => "rtvi-ai",
             "type" => "user-stopped-speaking",
             "data" => nil
           } = JSON.decode!(user_stopped)

    assert_receive {:ex_webrtc, ^client, {:data, ^client_channel, output}}, 5_000

    assert %{
             "label" => "rtvi-ai",
             "type" => "bot-output",
             "data" => %{
               "text" => "Echo: hello",
               "aggregated_by" => "sentence",
               "will_be_spoken" => false
             }
           } = JSON.decode!(output)

    assert_receive {:ex_webrtc, ^client, {:data, ^client_channel, turn_boundary}}, 5_000

    assert %{
             "id" => "evt_" <> _,
             "label" => "rtvi-ai",
             "type" => "bot-stopped-speaking",
             "data" => nil
           } = JSON.decode!(turn_boundary)

    assert [{connection, _value}] =
             Registry.lookup(Vxpipe.Gateway.WebRTC.Registry, {:connection, connection_id})

    connection_monitor = Process.monitor(connection)
    :ok = PeerConnection.close_data_channel(client, client_channel)

    assert_receive {:DOWN, ^connection_monitor, :process, ^connection, :shutdown}, 5_000

    assert [{_room, _value}] =
             Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {"tenant-development", room_id})
  end

  test "signals bot departure before closing WebRTC when the room ends" do
    room_id = "room-webrtc-ended-#{System.unique_integer([:positive, :monotonic])}"
    session_id = create_room_session(room_id)

    client = start_supervised!({PeerConnection, []})
    :ok = PeerConnection.controlling_process(client, self())

    {:ok, %DataChannel{ref: client_channel}} =
      PeerConnection.create_data_channel(client, "chat", ordered: true)

    {:ok, _transceiver} = PeerConnection.add_transceiver(client, :audio, direction: :sendrecv)
    {:ok, offer} = PeerConnection.create_offer(client)
    :ok = PeerConnection.set_local_description(client, offer)

    offer_conn =
      :post
      |> conn(
        "/api/rtvi/offer",
        JSON.encode!(%{
          "sdp" => offer.sdp,
          "type" => "offer",
          "pc_id" => nil,
          "restart_pc" => false,
          "requestData" => %{"session_id" => session_id}
        })
      )
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(@endpoint_options)

    assert offer_conn.status == 200

    assert %{"pc_id" => connection_id, "sdp" => answer_sdp, "type" => "answer"} =
             JSON.decode!(offer_conn.resp_body)

    :ok =
      PeerConnection.set_remote_description(
        client,
        %SessionDescription{type: :answer, sdp: answer_sdp}
      )

    assert_receive {:ex_webrtc, ^client, {:ice_candidate, candidate}}, 5_000
    patch_candidate(connection_id, candidate)
    assert_receive {:ex_webrtc, ^client, {:connection_state_change, :connected}}, 5_000

    assert_receive {:ex_webrtc, ^client, {:data_channel_state_change, ^client_channel, :open}},
                   5_000

    assert [{room, _value}] =
             Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {"tenant-development", room_id})

    assert [{connection, _value}] =
             Registry.lookup(Vxpipe.Gateway.WebRTC.Registry, {:connection, connection_id})

    connection_monitor = Process.monitor(connection)
    Process.exit(room, :shutdown)

    assert_receive {:ex_webrtc, ^client, {:data, ^client_channel, peer_left}}, 5_000

    assert %{"type" => "signalling", "message" => %{"type" => "peerLeft"}} =
             JSON.decode!(peer_left)

    assert_receive {:DOWN, ^connection_monitor, :process, ^connection, :shutdown}, 5_000
  end

  test "forwards microphone RTP to speech recognition while agent output is active" do
    configure_audio_capabilities(self())

    room_id = "room-full-duplex-#{System.unique_integer([:positive, :monotonic])}"
    session_id = create_audio_session(room_id)
    assert_receive {:test_tts_transport_started, tts_transport, _connection}

    client = start_supervised!({PeerConnection, []})
    :ok = PeerConnection.controlling_process(client, self())

    {:ok, %DataChannel{ref: client_channel}} =
      PeerConnection.create_data_channel(client, "chat", ordered: true)

    audio_track = MediaStreamTrack.new(:audio)

    {:ok, _transceiver} =
      PeerConnection.add_transceiver(client, audio_track, direction: :sendrecv)

    {:ok, offer} = PeerConnection.create_offer(client)
    :ok = PeerConnection.set_local_description(client, offer)

    offer_conn =
      :post
      |> conn(
        "/api/rtvi/offer",
        JSON.encode!(%{
          "sdp" => offer.sdp,
          "type" => "offer",
          "pc_id" => nil,
          "restart_pc" => false,
          "requestData" => %{"session_id" => session_id}
        })
      )
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(@endpoint_options)

    assert offer_conn.status == 200

    assert %{"pc_id" => connection_id, "sdp" => answer_sdp, "type" => "answer"} =
             JSON.decode!(offer_conn.resp_body)

    assert_receive {:test_stt_transport_started, stt_transport, _connection}

    :ok =
      PeerConnection.set_remote_description(
        client,
        %SessionDescription{type: :answer, sdp: answer_sdp}
      )

    assert_receive {:ex_webrtc, ^client, {:ice_candidate, candidate}}, 5_000
    patch_candidate(connection_id, candidate)
    assert_receive {:ex_webrtc, ^client, {:connection_state_change, :connected}}, 5_000

    assert_receive {:ex_webrtc, ^client, {:data_channel_state_change, ^client_channel, :open}},
                   5_000

    :ok =
      PeerConnection.send_data(
        client,
        client_channel,
        JSON.encode!(%{
          "id" => "client-ready-full-duplex",
          "label" => "rtvi-ai",
          "type" => "client-ready",
          "data" => %{"version" => "2.1.0"}
        })
      )

    assert %{"type" => "bot-ready"} = await_type(client, client_channel, "bot-ready", 5_000)

    :ok =
      PeerConnection.send_data(
        client,
        client_channel,
        JSON.encode!(%{
          "id" => "client-text-full-duplex",
          "label" => "rtvi-ai",
          "type" => "send-text",
          "data" => %{
            "content" => "keep speaking",
            "options" => %{"run_immediately" => true, "audio_response" => true}
          }
        })
      )

    assert %{"type" => "bot-output", "data" => %{"will_be_spoken" => true}} =
             await_type(client, client_channel, "bot-output", 5_000)

    assert_receive {:test_tts_control, ^tts_transport, _speak}
    assert_receive {:test_tts_control, ^tts_transport, _flush}

    empty_packet =
      Packet.new(<<>>,
        payload_type: 111,
        sequence_number: 1,
        timestamp: 0,
        ssrc: 123
      )

    assert :ok = PeerConnection.send_rtp(client, audio_track.id, empty_packet)

    stereo = stereo_opus_packet()

    packet =
      Packet.new(stereo,
        payload_type: 111,
        sequence_number: 2,
        timestamp: 960,
        ssrc: 123
      )

    assert :ok = PeerConnection.send_rtp(client, audio_track.id, packet)
    assert_receive {:test_stt_audio, ^stt_transport, normalized_stereo}, 5_000
    assert <<_configuration::5, 0::1, _frame_code::2, _rest::binary>> = normalized_stereo

    payload = mono_opus_packet()

    packet =
      Packet.new(payload,
        payload_type: 111,
        sequence_number: 3,
        timestamp: 1_920,
        ssrc: 123
      )

    assert :ok = PeerConnection.send_rtp(client, audio_track.id, packet)
    assert_receive {:test_stt_audio, ^stt_transport, normalized_mono}, 5_000

    assert {:ok, 1} =
             Vxpipe.Gateway.WebRTC.OpusInput.packet_channels(normalized_mono)

    refute_receive {:ex_webrtc, ^client, {:data, ^client_channel, _message}}

    TestSpeechToTextTransport.deliver(
      stt_transport,
      turn_message("StartOfTurn", 1, "actually make it shorter")
    )

    assert %{"type" => "bot-interrupted", "data" => nil} =
             receive_rtvi(client, client_channel, 5_000)

    assert %{
             "type" => "server-message",
             "data" => %{
               "t" => "vxpipe.turn",
               "d" => %{
                 "kind" => "interrupted",
                 "interrupted_by" => %{
                   "participant_id" => "part_" <> _,
                   "connection_id" => ^connection_id
                 }
               }
             }
           } = receive_rtvi(client, client_channel, 5_000)

    assert %{"type" => "user-started-speaking"} =
             receive_rtvi(client, client_channel, 5_000)

    assert %{
             "type" => "user-transcription",
             "data" => %{"text" => "actually make it shorter", "final" => false}
           } = receive_rtvi(client, client_channel, 5_000)

    TestSpeechToTextTransport.deliver(
      stt_transport,
      turn_message("EndOfTurn", 2, "actually make it shorter", "model")
    )

    assert %{"type" => "user-transcription", "data" => %{"final" => true}} =
             receive_rtvi(client, client_channel, 5_000)

    assert %{"type" => "user-stopped-speaking"} =
             receive_rtvi(client, client_channel, 5_000)

    assert %{
             "type" => "bot-output",
             "data" => %{
               "text" => "Echo: actually make it shorter",
               "will_be_spoken" => true
             }
           } = receive_rtvi(client, client_channel, 5_000)
  end

  defp create_audio_session(room_id) do
    options =
      Endpoint.init(
        cors: [],
        room_creation: [
          enabled: true,
          principal: [
            tenant_id: "tenant-development",
            actor_id: "actor-samples",
            scopes: ["rooms:create", "rooms:join"]
          ],
          trusted_call: [
            call_spec: TestTurnCall.call_spec(speech_to_text: true, text_to_speech: true),
            resource_id: "audio-turn-call-spec",
            revision: 1,
            host_tools: %{}
          ]
        ]
      )

    response =
      :post
      |> conn("/api/rooms", JSON.encode!(%{"room_id" => room_id}))
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(options)

    assert response.status == 201
    get_in(JSON.decode!(response.resp_body), ["session", "session_id"])
  end

  defp create_room_session(room_id) do
    create_conn =
      :post
      |> conn("/api/rooms", JSON.encode!(%{"room_id" => room_id}))
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(@endpoint_options)

    assert create_conn.status == 201

    session_conn =
      :post
      |> conn("/api/rooms/#{room_id}/sessions")
      |> Endpoint.call(@endpoint_options)

    assert session_conn.status == 201
    get_in(JSON.decode!(session_conn.resp_body), ["session", "session_id"])
  end

  defp patch_candidate(connection_id, %ICECandidate{} = candidate) do
    patch_conn =
      :patch
      |> conn(
        "/api/rtvi/offer",
        JSON.encode!(%{
          "pc_id" => connection_id,
          "candidates" => [
            %{
              "candidate" => candidate.candidate,
              "sdp_mid" => candidate.sdp_mid,
              "sdp_mline_index" => candidate.sdp_m_line_index
            }
          ]
        })
      )
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(@endpoint_options)

    assert patch_conn.status == 200
    assert %{"status" => "success"} = JSON.decode!(patch_conn.resp_body)
  end

  defp configure_audio_capabilities(observer) do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    speech_to_text = [
      providers: %{
        Flux.Session => [
          enabled: true,
          wire_module: TestSpeechToTextTransport,
          wire_options: [observer: observer, ready_on_start: true],
          media_ingress: [
            maximum_frames: 50,
            maximum_bytes: 262_144,
            maximum_age_ms: 2_000,
            maximum_consecutive_overflows: 5
          ]
        ]
      }
    ]

    text_to_speech = [
      providers: %{
        FluxTextToSpeech.Session => [
          enabled: true,
          wire_module: TestTextToSpeechTransport,
          wire_options: [observer: observer, ready_on_start: true],
          maximum_requests: 2
        ]
      }
    ]

    settings =
      original
      |> Keyword.put(:speech_to_text, speech_to_text)
      |> Keyword.put(:text_to_speech, text_to_speech)
      |> Keyword.update!(:agent_runtime, &Keyword.put(&1, :fixture, {TestEchoModelProvider, []}))

    Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, settings)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)
  end

  defp await_type(client, channel, type, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await_type(client, channel, type, deadline)
  end

  defp do_await_type(client, channel, type, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:ex_webrtc, ^client, {:data, ^channel, payload}} ->
        message = JSON.decode!(payload)

        if message["type"] == type do
          message
        else
          do_await_type(client, channel, type, deadline)
        end
    after
      remaining -> flunk("timed out waiting for #{type}")
    end
  end

  defp receive_rtvi(client, channel, timeout_ms) do
    receive do
      {:ex_webrtc, ^client, {:data, ^channel, payload}} -> JSON.decode!(payload)
    after
      timeout_ms -> flunk("timed out waiting for an RTVI message")
    end
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

    message = if trigger == nil, do: message, else: Map.put(message, "trigger", trigger)
    JSON.encode!(message)
  end

  defp mono_opus_packet do
    opus_packet(1)
  end

  defp stereo_opus_packet do
    opus_packet(2)
  end

  defp opus_packet(channels) do
    encoder = OpusEncoder.create(48_000, channels, 2_048, 64_000, 3_001)

    pcm =
      for sample <- 0..959, channel <- 1..channels, into: <<>> do
        frequency = if channel == 1, do: 440, else: 660
        value = round(:math.sin(2 * :math.pi() * frequency * sample / 48_000) * 16_000)
        <<value::little-signed-16>>
      end

    assert {:ok, payload} = OpusEncoder.encode_packet(encoder, pcm, 960)
    payload
  end
end
