defmodule Vxpipe.Gateway.Integration.RTVIDeepgramFluxTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias ExRTP.Packet

  alias ExWebRTC.{
    DataChannel,
    ICECandidate,
    MediaStreamTrack,
    PeerConnection,
    SessionDescription
  }

  alias ExWebRTC.Media.Ogg.Reader

  alias Vxpipe.Providers.Deepgram.TTSSocket

  alias Vxpipe.CallEngine.{TestEchoModelProvider, TestTenantCredentialSource, TestTurnCall}
  alias Vxpipe.Gateway.HTTP.Endpoint

  @moduletag :live_providers
  @moduletag :live_deepgram
  @moduletag capture_log: true
  @moduletag timeout: 60_000

  @endpoint_options Endpoint.init(
                      cors: [],
                      room_creation: [
                        enabled: true,
                        trusted_call: [
                          call_spec:
                            TestTurnCall.call_spec(speech_to_text: true, text_to_speech: true),
                          resource_id: "live-speech-call-spec",
                          revision: 1,
                          host_tools: %{}
                        ],
                        principal: [
                          tenant_id: "tenant-development",
                          actor_id: "actor-samples",
                          scopes: ["rooms:create", "rooms:join"]
                        ]
                      ]
                    )

  setup do
    original_settings =
      Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    speech_to_text = [
      providers: %{
        Vxpipe.Providers.Deepgram.STTSession => [
          enabled: true,
          wire_options: [connect_timeout: 10_000, receive_timeout: 30_000],
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
        Vxpipe.Providers.Deepgram.TTSSession => [
          enabled: true,
          wire_module: TTSSocket,
          wire_options: [connect_timeout: 10_000, receive_timeout: 30_000],
          maximum_requests: 4
        ]
      }
    ]

    application_settings =
      original_settings
      |> Keyword.put(:speech_to_text, speech_to_text)
      |> Keyword.put(:text_to_speech, text_to_speech)
      |> Keyword.update!(:agent_runtime, &Keyword.put(&1, :fixture, {TestEchoModelProvider, []}))
      |> Keyword.put(
        :credential_source,
        {TestTenantCredentialSource,
         {self(),
          %{
            {"tenant-development", "deepgram", "default"} => %{
              "api_key" => System.fetch_env!("DEEPGRAM_API_KEY")
            }
          }}}
      )

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      application_settings
    )

    on_exit(fn ->
      Application.put_env(
        :vxpipe_call_engine,
        Vxpipe.CallEngine.Application,
        original_settings
      )
    end)

    :ok
  end

  test "projects a WebRTC microphone turn through Flux and RTVI to the agent" do
    room_id = "room-live-flux-#{System.unique_integer([:positive, :monotonic])}"
    session_id = create_room_session(room_id)

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
          "id" => "client-ready-live",
          "label" => "rtvi-ai",
          "type" => "client-ready",
          "data" => %{
            "version" => "2.1.0",
            "about" => %{"library" => "vxpipe-integration-test"}
          }
        })
      )

    assert %{"type" => "bot-ready"} = await_rtvi_message(client, client_channel, 5_000)

    assert {:ok, reader} = Reader.open(System.fetch_env!("DEEPGRAM_LIVE_AUDIO"))
    on_exit(fn -> Reader.close(reader) end)
    stream_rtp(reader, client, audio_track.id, 0, 0)

    messages = await_completed_turn(client, client_channel, 15_000, [])
    message_types = Enum.map(messages, &Map.fetch!(&1, "type"))

    assert_subsequence(message_types, [
      "user-started-speaking",
      "user-transcription",
      "user-stopped-speaking",
      "bot-output",
      "bot-started-speaking",
      "bot-output",
      "bot-output",
      "bot-stopped-speaking"
    ])

    refute Enum.any?(message_types, &String.starts_with?(&1, "user-mute-"))

    final_transcription =
      messages
      |> Enum.filter(&match?(%{"type" => "user-transcription", "data" => %{"final" => true}}, &1))
      |> List.last()

    assert %{"data" => %{"text" => final_text, "user_id" => "part_" <> _}} =
             final_transcription

    assert String.trim(final_text) != ""

    echoed_text =
      messages
      |> Enum.filter(
        &match?(%{"type" => "bot-output", "data" => %{"spoken_status" => "new"}}, &1)
      )
      |> Enum.map_join(" ", &get_in(&1, ["data", "text"]))

    assert echoed_text == "Echo: " <> String.trim(final_text)

    assert %{"data" => %{"will_be_spoken" => true, "spoken_status" => "new"}} =
             Enum.find(messages, &match?(%{"type" => "bot-output"}, &1))

    assert Enum.any?(
             messages,
             &match?(%{"type" => "bot-output", "data" => %{"spoken_status" => "completed"}}, &1)
           )

    assert Enum.any?(messages, fn
             %{
               "type" => "bot-output",
               "data" => %{
                 "text" => text,
                 "spoken_status" => "in-progress",
                 "spoken_progress" => %{
                   "accumulated_text" => "",
                   "remaining_text" => remaining_text
                 }
               }
             } ->
               remaining_text == text

             _other ->
               false
           end)

    assert %Packet{payload: payload} = await_output_rtp(client, output_track.id, 5_000)
    assert byte_size(payload) > 0
  end

  defp stream_rtp(reader, client, track_id, sequence_number, timestamp) do
    case Reader.next_packet(reader) do
      {:ok, {payload, duration_ms}, reader} ->
        packet =
          Packet.new(payload,
            payload_type: 111,
            sequence_number: rem(sequence_number, 65_536),
            timestamp: timestamp,
            ssrc: 123
          )

        :ok = PeerConnection.send_rtp(client, track_id, packet)
        pace(duration_ms)

        stream_rtp(
          reader,
          client,
          track_id,
          sequence_number + 1,
          timestamp + duration_ms * 48
        )

      :eof ->
        :ok

      {:error, reason} ->
        flunk("could not read the Opus fixture: #{inspect(reason)}")
    end
  end

  defp await_completed_turn(client, channel, timeout_ms, messages) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await_completed_turn(client, channel, deadline, messages)
  end

  defp do_await_completed_turn(client, channel, deadline, messages) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    message = await_rtvi_message(client, channel, remaining)
    messages = messages ++ [message]

    if message["type"] == "bot-stopped-speaking" do
      messages
    else
      do_await_completed_turn(client, channel, deadline, messages)
    end
  end

  defp await_rtvi_message(client, channel, timeout_ms) do
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

  defp pace(0), do: :ok

  defp pace(duration_ms) do
    reference = make_ref()
    _timer = Process.send_after(self(), {:audio_pace, reference}, duration_ms)
    assert_receive {:audio_pace, ^reference}, duration_ms + 100
  end

  defp create_room_session(room_id) do
    create_conn =
      :post
      |> conn("/api/rooms", JSON.encode!(%{"room_id" => room_id}))
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(@endpoint_options)

    assert create_conn.status == 201

    get_in(JSON.decode!(create_conn.resp_body), ["session", "session_id"])
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
