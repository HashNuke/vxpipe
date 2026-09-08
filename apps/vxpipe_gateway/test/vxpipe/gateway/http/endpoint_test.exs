defmodule Vxpipe.Gateway.HTTP.EndpointTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Gateway.HTTP.Endpoint

  @allowed_origin "https://client.example.test"
  @request_stop_event [:vxpipe, :gateway, :http, :request, :stop]
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

  test "reports bounded request outcomes without request data" do
    attach_request_events()
    sentinel = "must-not-enter-metrics"

    health_conn =
      :get
      |> conn("/healthz?probe=#{sentinel}")
      |> Endpoint.call(@endpoint_options)

    assert health_conn.status == 200

    assert_request_event(:health_check, :ok, 200, sentinel)

    missing_conn =
      :get
      |> conn("/not-a-route/#{sentinel}")
      |> Endpoint.call(@endpoint_options)

    assert missing_conn.status == 404

    assert_request_event(:unknown, :client_error, 404, sentinel)
  end

  test "reports a bounded exception outcome and reraises" do
    attach_request_events()

    assert_raise Plug.Parsers.ParseError, fn ->
      :post
      |> conn("/api/rooms", "{invalid-json")
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(@endpoint_options)
    end

    assert_receive {:telemetry_event, @request_stop_event, measurements,
                    %{operation: :room_create, outcome: :exception, status: nil}}

    assert is_integer(measurements.duration)
    assert measurements.duration >= 0
  end

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

  test "starts a trusted definition call and issues its entry caller session" do
    room_id = "room-definition-#{System.unique_integer([:positive, :monotonic])}"

    conn =
      :post
      |> conn("/api/rooms", JSON.encode!(%{"room_id" => room_id}))
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(trusted_endpoint_options())

    assert conn.status == 201

    assert %{
             "room" => %{
               "tenant_id" => "tenant-development",
               "room_id" => ^room_id,
               "incarnation_id" => incarnation_id
             },
             "participant" => %{
               "participant_id" => participant_id,
               "role" => "human",
               "room_id" => ^room_id,
               "state" => "joined"
             },
             "session" => %{
               "session_id" => session_id,
               "transport" => %{
                 "endpoint" => "/api/rtvi/offer",
                 "request_data" => %{"session_id" => session_id},
                 "type" => "smallwebrtc"
               }
             }
           } = JSON.decode!(conn.resp_body)

    assert "rinc_" <> _ = incarnation_id
    assert "part_" <> _ = participant_id
    assert "sess_" <> _ = session_id
  end

  test "rejects a trusted definition call without a valid room ID" do
    conn =
      :post
      |> conn("/api/rooms", JSON.encode!(%{}))
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(trusted_endpoint_options())

    assert conn.status == 400
    assert %{"error" => %{"code" => "invalid_call_invocation"}} = JSON.decode!(conn.resp_body)
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

  defp trusted_call_options do
    [
      resource_id: "sample-call",
      revision: 1,
      definition: %{
        schema_version: "20260906.02",
        entry_caller: "caller",
        entry_receiver: "receiver",
        defaults: %{capabilities: %{}},
        call_variables: %{sections: %{}},
        participants: %{
          "caller" => %{
            type: "human",
            connection: %{service: "web", mode: "receive", admission: "start_call"}
          },
          "receiver" => %{
            type: "agent",
            prompt: "Answer briefly.",
            first_message: %{mode: "wait_for_input"},
            capabilities: %{model_inference: "sample-model"},
            tools: %{},
            transfers: []
          }
        },
        limits: %{max_duration_ms: 60_000}
      },
      capability_profiles: %{
        "sample-model" => %{
          kind: :model_inference,
          provider: :req_llm,
          options: %{model: "test:scripted"}
        }
      },
      host_tools: %{}
    ]
  end

  defp trusted_endpoint_options do
    Endpoint.init(
      cors: [],
      room_creation: [
        enabled: true,
        principal: [
          tenant_id: "tenant-development",
          actor_id: "actor-samples",
          scopes: ["rooms:create", "rooms:join"]
        ],
        trusted_call: trusted_call_options()
      ]
    )
  end

  def handle_request_event(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry_event, event, measurements, metadata})
  end

  defp attach_request_events do
    handler_id = {__MODULE__, self(), make_ref()}

    :ok =
      :telemetry.attach(
        handler_id,
        @request_stop_event,
        &__MODULE__.handle_request_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp assert_request_event(operation, outcome, status, sentinel) do
    assert_receive {:telemetry_event, @request_stop_event, measurements,
                    %{operation: ^operation, outcome: ^outcome, status: ^status} = metadata}

    assert is_integer(measurements.duration)
    assert measurements.duration >= 0
    assert Map.keys(measurements) == [:duration]
    assert metadata |> Map.keys() |> Enum.sort() == [:operation, :outcome, :status]
    refute inspect({measurements, metadata}) =~ sentinel
  end
end
