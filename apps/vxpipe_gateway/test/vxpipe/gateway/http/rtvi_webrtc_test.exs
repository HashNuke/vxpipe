defmodule Vxpipe.Gateway.HTTP.RTVIWebRTCTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias ExWebRTC.{DataChannel, ICECandidate, PeerConnection, SessionDescription}
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

    assert [{connection, _value}] =
             Registry.lookup(Vxpipe.Gateway.WebRTC.Registry, {:connection, connection_id})

    connection_monitor = Process.monitor(connection)
    :ok = PeerConnection.close_data_channel(client, client_channel)

    assert_receive {:DOWN, ^connection_monitor, :process, ^connection, :shutdown}, 5_000

    assert [{_room, _value}] =
             Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {"tenant-development", room_id})
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
end
