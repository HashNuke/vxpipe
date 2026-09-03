defmodule Vxpipe.Gateway.HTTP.EndpointTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Gateway.HTTP.Endpoint

  @allowed_origin "https://client.example.test"
  @endpoint_options Endpoint.init(
                      cors: [
                        allowed_origins: [@allowed_origin],
                        allowed_methods: ["POST", "PATCH", "OPTIONS"],
                        allowed_headers: ["content-type", "authorization"],
                        allow_credentials: false
                      ]
                    )
  @room_endpoint_options Endpoint.init(
                           cors: [],
                           room_creation: [
                             enabled: true,
                             principal: [
                               tenant_id: "tenant-development",
                               actor_id: "actor-samples",
                               scopes: ["rooms:create", "rooms:join"]
                             ]
                           ]
                         )
  @unscoped_room_endpoint_options Endpoint.init(
                                    cors: [],
                                    room_creation: [
                                      enabled: true,
                                      principal: [
                                        tenant_id: "tenant-development",
                                        actor_id: "actor-samples",
                                        scopes: []
                                      ]
                                    ]
                                  )

  test "answers health checks" do
    conn =
      :get
      |> conn("/healthz")
      |> Endpoint.call(@endpoint_options)

    assert conn.status == 200
    assert conn.resp_body == "ok"
  end

  test "answers a preflight request from a configured origin" do
    conn =
      :options
      |> conn("/api/rtvi/offer")
      |> put_req_header("origin", @allowed_origin)
      |> put_req_header("access-control-request-method", "PATCH")
      |> put_req_header("access-control-request-headers", "content-type,authorization")
      |> Endpoint.call(@endpoint_options)

    assert conn.status == 204
    assert get_resp_header(conn, "access-control-allow-origin") == [@allowed_origin]
    assert get_resp_header(conn, "access-control-allow-methods") == ["POST,PATCH,OPTIONS"]
    assert get_resp_header(conn, "access-control-allow-headers") == ["content-type,authorization"]
    assert get_resp_header(conn, "access-control-allow-credentials") == []
  end

  test "does not grant a non-configured origin" do
    conn =
      :get
      |> conn("/healthz")
      |> put_req_header("origin", "https://untrusted.example.test")
      |> Endpoint.call(@endpoint_options)

    assert conn.status == 200
    assert get_resp_header(conn, "access-control-allow-origin") == []
  end

  test "creates a room using the gateway's configured principal" do
    conn =
      :post
      |> conn("/api/rooms", JSON.encode!(%{"room_id" => "room_client-request"}))
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(@room_endpoint_options)

    assert conn.status == 201
    assert ["application/json; charset=utf-8"] = get_resp_header(conn, "content-type")

    assert %{
             "room" => %{
               "tenant_id" => "tenant-development",
               "created_by_actor_id" => "actor-samples",
               "lifecycle" => "open",
               "room_id" => "room_client-request",
               "incarnation_id" => "rinc_" <> _,
               "created_by_command_id" => "cmd_" <> _
             }
           } = JSON.decode!(conn.resp_body)
  end

  test "rejects room creation without a valid client room ID" do
    conn =
      :post
      |> conn("/api/rooms", JSON.encode!(%{}))
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(@room_endpoint_options)

    assert conn.status == 400
    assert %{"error" => %{"code" => "invalid_command"}} = JSON.decode!(conn.resp_body)
  end

  test "does not expose room creation when the slice is disabled" do
    conn =
      :post
      |> conn("/api/rooms")
      |> Endpoint.call(@endpoint_options)

    assert conn.status == 404
  end

  test "requires the configured principal to have room-creation scope" do
    conn =
      :post
      |> conn("/api/rooms")
      |> Endpoint.call(@unscoped_room_endpoint_options)

    assert conn.status == 403
    assert %{"error" => %{"code" => "not_authorized"}} = JSON.decode!(conn.resp_body)
  end

  test "admits a participant and issues a bound Small WebRTC session" do
    room_id = "room-session-#{System.unique_integer([:positive, :monotonic])}"

    create_conn =
      :post
      |> conn("/api/rooms", JSON.encode!(%{"room_id" => room_id}))
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(@room_endpoint_options)

    assert create_conn.status == 201

    session_conn =
      :post
      |> conn("/api/rooms/#{room_id}/sessions")
      |> Endpoint.call(@room_endpoint_options)

    assert session_conn.status == 201

    assert %{
             "participant" => %{
               "participant_id" => "part_" <> _,
               "role" => "human",
               "room_id" => ^room_id,
               "state" => "joined"
             },
             "session" => %{
               "expires_at" => expires_at,
               "session_id" => session_id,
               "transport" => %{
                 "endpoint" => "/api/rtvi/offer",
                 "request_data" => %{"session_id" => request_session_id},
                 "type" => "smallwebrtc"
               }
             }
           } = JSON.decode!(session_conn.resp_body)

    assert "sess_" <> _ = session_id
    assert request_session_id == session_id
    assert {:ok, expires_at, 0} = DateTime.from_iso8601(expires_at)
    assert DateTime.diff(expires_at, DateTime.utc_now(), :second) >= 240
  end
end
