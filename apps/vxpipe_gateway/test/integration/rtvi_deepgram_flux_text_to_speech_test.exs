defmodule Vxpipe.Gateway.Integration.RTVIDeepgramFluxTextToSpeechTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias ExRTP.Packet
  alias ExWebRTC.{DataChannel, ICECandidate, MediaStreamTrack, PeerConnection, SessionDescription}

  alias Vxpipe.Providers.Deepgram.TTSSocket

  alias Vxpipe.CallEngine.{TestEchoModelProvider, TestTenantCredentialSource, TestTurnCall}
  alias Vxpipe.Gateway.HTTP.Endpoint

  @moduletag :integration
  @moduletag live_provider: "deepgram"
  @moduletag skip: System.get_env("VXPIPE_LIVE") != "1"
  @moduletag capture_log: true
  @moduletag timeout: 60_000

  @endpoint_options Endpoint.init(
                      cors: [],
                      room_creation: [
                        enabled: true,
                        trusted_call: [
                          call_spec:
                            TestTurnCall.call_spec(speech_to_text: false, text_to_speech: true),
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
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

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

    settings =
      original
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

    Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, settings)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  test "plays a long turn completely and queues text submitted during playback" do
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

    # Keep one long sentence so the two logical turns each produce one speech segment.
    first_input = "Hello again and how are you feeling about what we should talk about?"
    second_input = "This arrived while the first response was playing."
    first_response = "Echo: " <> first_input
    second_response = "Echo: " <> second_input

    :ok =
      PeerConnection.send_data(
        client,
        client_channel,
        JSON.encode!(%{
          "id" => "client-text-long-live-tts",
          "label" => "rtvi-ai",
          "type" => "send-text",
          "data" => %{
            "content" => first_input,
            "options" => %{"audio_response" => true, "run_immediately" => true}
          }
        })
      )

    messages = await_type(client, client_channel, "bot-started-speaking", 15_000, [])

    :ok =
      PeerConnection.send_data(
        client,
        client_channel,
        JSON.encode!(%{
          "id" => "client-text-during-playback-live-tts",
          "label" => "rtvi-ai",
          "type" => "send-text",
          "data" => %{
            "content" => second_input,
            "options" => %{"audio_response" => true, "run_immediately" => false}
          }
        })
      )

    messages =
      await_type_count(client, client_channel, "bot-stopped-speaking", 2, 30_000, messages)

    types = Enum.map(messages, &Map.fetch!(&1, "type"))

    assert_subsequence(types, [
      "user-started-speaking",
      "user-stopped-speaking",
      "bot-output",
      "bot-started-speaking",
      "bot-output",
      "bot-output",
      "bot-stopped-speaking",
      "bot-output",
      "bot-started-speaking",
      "bot-output",
      "bot-output",
      "bot-stopped-speaking"
    ])

    refute Enum.any?(types, &String.starts_with?(&1, "user-mute-"))

    new_outputs =
      for %{
            "type" => "bot-output",
            "data" => %{
              "text" => text,
              "will_be_spoken" => true,
              "spoken_status" => "new"
            }
          } <- messages,
          do: text

    assert new_outputs == [first_response, second_response]

    assert Enum.count(
             messages,
             &match?(%{"type" => "bot-output", "data" => %{"spoken_status" => "completed"}}, &1)
           ) == 2

    assert Enum.count(messages, &match?(%{"type" => "bot-stopped-speaking"}, &1)) == 2

    in_progress_outputs =
      Enum.filter(
        messages,
        &match?(%{"type" => "bot-output", "data" => %{"spoken_status" => "in-progress"}}, &1)
      )

    assert length(in_progress_outputs) == 2

    assert Enum.all?(in_progress_outputs, fn %{
                                               "data" => %{
                                                 "text" => text,
                                                 "spoken_progress" => %{
                                                   "accumulated_text" => "",
                                                   "remaining_text" => remaining_text
                                                 }
                                               }
                                             } ->
             remaining_text == text
           end)

    packets = drain_output_rtp(client, output_track.id, [])
    assert Enum.all?(packets, &(byte_size(&1.payload) > 0))

    turn_start_indices =
      packets
      |> Enum.with_index()
      |> Enum.filter(fn {packet, _index} -> packet.marker end)
      |> Enum.map(fn {_packet, index} -> index end)

    assert [0, second_turn_start] = turn_start_indices
    assert second_turn_start > 100
    assert length(packets) > second_turn_start
  end

  defp await_type(client, channel, type, timeout_ms, messages) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await_type(client, channel, type, deadline, messages)
  end

  defp do_await_type(client, channel, type, deadline, messages) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)
    message = await_rtvi(client, channel, remaining)
    messages = messages ++ [message]

    if message["type"] == type do
      messages
    else
      do_await_type(client, channel, type, deadline, messages)
    end
  end

  defp await_type_count(client, channel, type, count, timeout_ms, messages) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await_type_count(client, channel, type, count, deadline, messages)
  end

  defp do_await_type_count(client, channel, type, count, deadline, messages) do
    occurrences = Enum.count(messages, &(&1["type"] == type))

    if occurrences >= count do
      messages
    else
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)
      message = await_rtvi(client, channel, remaining)
      do_await_type_count(client, channel, type, count, deadline, messages ++ [message])
    end
  end

  defp drain_output_rtp(client, track_id, packets) do
    receive do
      {:ex_webrtc, ^client, {:rtp, ^track_id, _rid, %Packet{} = packet}} ->
        drain_output_rtp(client, track_id, [packet | packets])
    after
      0 -> Enum.reverse(packets)
    end
  end

  defp await_rtvi(client, channel, timeout_ms) do
    receive do
      {:ex_webrtc, ^client, {:data, ^channel, payload}} -> JSON.decode!(payload)
    after
      timeout_ms -> flunk("timed out waiting for an RTVI message")
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
