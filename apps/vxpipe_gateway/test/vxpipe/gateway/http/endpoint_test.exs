defmodule Vxpipe.Gateway.HTTP.EndpointTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Gateway.HTTP.Endpoint
  alias Vxpipe.Gateway.{Session, TrustedCall}

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

  test "starts a trusted call from a call spec and issues its entry caller session" do
    room_id = "room-call-spec-#{System.unique_integer([:positive, :monotonic])}"

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

  test "pins trusted tool visibility and ignores a browser visibility field" do
    room_id = "room-visibility-#{System.unique_integer([:positive, :monotonic])}"

    call_spec =
      trusted_call_options()
      |> Keyword.fetch!(:call_spec)
      |> Map.put(:tool_visibility, "hidden")
      |> Map.put(:tool_visibility_overrides, %{
        "receiver" => %{"get_current_time" => "hidden"}
      })

    conn =
      :post
      |> conn(
        "/api/rooms",
        JSON.encode!(%{"room_id" => room_id, "tool_visibility" => "full"})
      )
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(
        trusted_endpoint_options(call_spec: call_spec, tool_visibility: "metadata")
      )

    assert conn.status == 201
    public_session = get_in(JSON.decode!(conn.resp_body), ["session"])
    session_id = public_session["session_id"]

    refute Map.has_key?(public_session, "tool_visibility")

    assert {:ok, session} = Session.claim(session_id)
    assert session.tool_visibility.default == :metadata
    assert session.tool_visibility.overrides == %{}
  end

  test "uses trusted initial variables instead of browser input" do
    room_id = "room-initial-variables-#{System.unique_integer([:positive, :monotonic])}"
    call_spec = call_spec_with_order_variables()

    conn =
      :post
      |> conn(
        "/api/rooms",
        JSON.encode!(%{
          "room_id" => room_id,
          "variables" => %{"order" => %{"id" => "browser-value"}}
        })
      )
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(
        trusted_endpoint_options(
          call_spec: call_spec,
          initial_variables: %{"order" => %{"id" => 123}}
        )
      )

    assert conn.status == 503

    assert %{
             "error" => %{
               "code" => "call_spec_resolution_failed",
               "details" => %{"path" => ["variables", "order"]}
             }
           } = JSON.decode!(conn.resp_body)
  end

  test "keeps configured initial variables out of trusted-call inspection" do
    sentinel = "private-order-sentinel"

    options =
      trusted_call_options()
      |> Keyword.put(:call_spec, call_spec_with_order_variables())
      |> Keyword.put(:initial_variables, %{"order" => %{"id" => sentinel}})

    assert {:ok, trusted_call} = TrustedCall.new(options)
    assert trusted_call.initial_variables == %{"order" => %{"id" => sentinel}}
    refute inspect(trusted_call) =~ sentinel
  end

  test "rejects a trusted call without a valid room ID" do
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
      call_spec: %{
        schema_version: "20260915.01",
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
            capabilities: %{model_inference: %{provider: "fixture", model: "test:scripted"}},
            tools: %{
              "get_current_time" => %{type: "host", tool: "get_current_time"}
            },
            transfers: []
          }
        },
        limits: %{max_duration_ms: 60_000}
      },
      host_tools: %{
        "get_current_time" => Vxpipe.CallEngine.Tool.CurrentTime
      }
    ]
  end

  defp call_spec_with_order_variables do
    trusted_call_options()
    |> Keyword.fetch!(:call_spec)
    |> Map.put(:call_variables, %{
      sections: %{
        "order" => %{
          schema: %{
            "type" => "object",
            "properties" => %{"id" => %{"type" => "string"}},
            "additionalProperties" => false
          }
        }
      }
    })
    |> put_in(
      [:participants, "receiver", :variable_permissions],
      %{"order" => ["read"]}
    )
  end

  defp trusted_endpoint_options(trusted_overrides \\ []) do
    trusted_call = Keyword.merge(trusted_call_options(), trusted_overrides)

    Endpoint.init(
      cors: [],
      room_creation: [
        enabled: true,
        principal: [
          tenant_id: "tenant-development",
          actor_id: "actor-samples",
          scopes: ["rooms:create", "rooms:join"]
        ],
        trusted_call: trusted_call
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
