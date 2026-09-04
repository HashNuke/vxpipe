defmodule Vxpipe.Gateway.Integration.RTVIDeepgramFluxTextToSpeechTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias ExRTP.Packet
  alias ExWebRTC.{DataChannel, ICECandidate, MediaStreamTrack, PeerConnection, SessionDescription}

  alias Vxpipe.CallEngine.Provider.Deepgram.{
    FluxTextToSpeech,
    FluxTextToSpeechSocket
  }

  alias Vxpipe.Gateway.HTTP.Endpoint

  @moduletag :integration
  @moduletag capture_log: true
  @moduletag timeout: 60_000

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

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    text_to_speech = [
      enabled: true,
      provider: FluxTextToSpeech,
      provider_options: [
        api_key: System.fetch_env!("DEEPGRAM_API_KEY"),
        model: "flux-haley-en",
        encoding: :linear16,
        sample_rate: 48_000
      ],
      transport: {FluxTextToSpeechSocket, [connect_timeout: 10_000, receive_timeout: 30_000]},
      maximum_requests: 4
    ]

    settings =
      original
      |> Keyword.put(:speech_to_text, enabled: false)
      |> Keyword.put(:text_to_speech, text_to_speech)

    Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, settings)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  test "delivers a spoken RTVI text turn as paced Opus RTP" do
    room_id = "room-live-tts-#{System.unique_integer([:positive, :monotonic])}"
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
          "requestData" => %{"session_id" => session_id}
        })
      )
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(@endpoint_options)

    assert offer_conn.status == 200

    assert %{"pc_id" => connection_id, "sdp" => answer_sdp} =
             JSON.decode!(offer_conn.resp_body)

    :ok =
      PeerConnection.set_remote_description(
        client,
        %SessionDescription{type: :answer, sdp: answer_sdp}
      )

    assert_receive {:ex_webrtc, ^client,
                    {:track, %MediaStreamTrack{kind: :audio} = output_track}},
                   5_000

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
          "id" => "client-ready-live-tts",
          "label" => "rtvi-ai",
          "type" => "client-ready",
          "data" => %{"version" => "2.1.0"}
        })
      )

    assert %{"type" => "bot-ready"} = await_rtvi(client, client_channel, 5_000)

    :ok =
      PeerConnection.send_data(
        client,
        client_channel,
        JSON.encode!(%{
          "id" => "client-text-live-tts",
          "label" => "rtvi-ai",
          "type" => "send-text",
          "data" => %{
            "content" => "hello",
            "options" => %{"audio_response" => true, "run_immediately" => true}
          }
        })
      )

    messages = await_stopped(client, client_channel, 15_000, [])
    types = Enum.map(messages, &Map.fetch!(&1, "type"))

    assert_subsequence(types, [
      "user-started-speaking",
      "user-stopped-speaking",
      "bot-output",
      "user-mute-started",
      "bot-started-speaking",
      "bot-output",
      "bot-output",
      "bot-stopped-speaking"
    ])

    assert %{
             "data" => %{
               "text" => "Echo: hello",
               "will_be_spoken" => true,
               "spoken_status" => "new"
             }
           } = Enum.find(messages, &match?(%{"type" => "bot-output"}, &1))

    assert Enum.any?(
             messages,
             &match?(%{"type" => "bot-output", "data" => %{"spoken_status" => "completed"}}, &1)
           )

    assert %Packet{payload: payload} = await_output_rtp(client, output_track.id, 5_000)
    assert byte_size(payload) > 0
  end

  defp await_stopped(client, channel, timeout_ms, messages) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await_stopped(client, channel, deadline, messages)
  end

  defp do_await_stopped(client, channel, deadline, messages) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)
    message = await_rtvi(client, channel, remaining)
    messages = messages ++ [message]

    if message["type"] == "bot-stopped-speaking" do
      messages
    else
      do_await_stopped(client, channel, deadline, messages)
    end
  end

  defp await_rtvi(client, channel, timeout_ms) do
    receive do
      {:ex_webrtc, ^client, {:data, ^channel, payload}} -> JSON.decode!(payload)
    after
      timeout_ms -> flunk("timed out waiting for an RTVI message")
    end
  end

  defp await_output_rtp(client, track_id, timeout_ms) do
    receive do
      {:ex_webrtc, ^client, {:rtp, ^track_id, _rid, %Packet{} = packet}} -> packet
    after
      timeout_ms -> flunk("timed out waiting for agent Opus RTP")
    end
  end

  defp assert_subsequence(values, expected) do
    remaining =
      Enum.reduce(values, expected, fn value, remaining ->
        case remaining do
          [^value | rest] -> rest
          _other -> remaining
        end
      end)

    assert remaining == []
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
  end
end
