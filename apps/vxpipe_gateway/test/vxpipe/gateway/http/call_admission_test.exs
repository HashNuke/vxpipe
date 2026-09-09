defmodule Vxpipe.Gateway.HTTP.CallAdmissionTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Gateway.HTTP.Endpoint
  alias Vxpipe.Gateway.TestAdmissionBackend

  @origin "https://client.example.test"
  @api_key "vxp_test-only-gateway-key"
  @join_token "vxj_test-only-gateway-token"

  setup do
    backend =
      start_supervised!(
        {TestAdmissionBackend, api_key: @api_key, join_token: @join_token, observer: self()}
      )

    [backend: backend, endpoint: endpoint_options(backend)]
  end

  test "prepares through API-key auth without granting CORS or exposing private input", context do
    sentinel = "private-order-sentinel"

    conn =
      :post
      |> conn(
        prepare_path(),
        JSON.encode!(%{
          "initial_variables" => %{"order" => %{"id" => sentinel}},
          "join_token_ttl_seconds" => 900
        })
      )
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer #{@api_key}")
      |> put_req_header("origin", @origin)
      |> Endpoint.call(context.endpoint)

    assert conn.status == 201
    assert get_resp_header(conn, "access-control-allow-origin") == []

    assert %{
             "call" => %{
               "call_id" => call_id,
               "created_at" => "2026-09-09T12:00:00.000000Z",
               "started_at" => nil,
               "state" => "prepared"
             },
             "join_token" => %{
               "expires_at" => "2026-09-09T12:15:00.000000Z",
               "token" => @join_token
             }
           } = body(conn)

    assert call_id == TestAdmissionBackend.call_id()
    refute conn.resp_body =~ sentinel
    refute conn.resp_body =~ @api_key

    assert [
             {:authenticate, tenant_key},
             {:prepare, tenant_key, participant_key, %{"order" => %{"id" => ^sentinel}}, 900}
           ] = TestAdmissionBackend.operations(context.backend)

    assert tenant_key == TestAdmissionBackend.tenant_key()
    assert participant_key == TestAdmissionBackend.participant_key()
    refute_receive {:test_admission_started, _incarnation_id, _started_at}
  end

  test "rejects missing API-key credentials before preparation", context do
    conn =
      :post
      |> conn(prepare_path(), JSON.encode!(%{"initial_variables" => %{}}))
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(context.endpoint)

    assert conn.status == 401
    assert %{"error" => %{"code" => "invalid_api_key"}} = body(conn)
    assert TestAdmissionBackend.operations(context.backend) == []
  end

  test "rejects an invalid API key independently of CORS", context do
    conn =
      :post
      |> conn(prepare_path(), JSON.encode!(%{"initial_variables" => %{}}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer vxp_invalid")
      |> put_req_header("origin", @origin)
      |> Endpoint.call(context.endpoint)

    assert conn.status == 401
    assert %{"error" => %{"code" => "invalid_api_key"}} = body(conn)
    assert get_resp_header(conn, "access-control-allow-origin") == []
    assert [{:authenticate, tenant_key}] = TestAdmissionBackend.operations(context.backend)
    assert tenant_key == TestAdmissionBackend.tenant_key()
  end

  test "issues another existing-call token through the backend-only route", context do
    conn =
      :post
      |> conn(token_path(), JSON.encode!(%{"join_token_ttl_seconds" => 600}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer #{@api_key}")
      |> put_req_header("origin", @origin)
      |> Endpoint.call(context.endpoint)

    assert conn.status == 201
    assert get_resp_header(conn, "access-control-allow-origin") == []

    assert %{
             "call_id" => call_id,
             "join_token" => %{
               "token" => @join_token,
               "expires_at" => "2026-09-09T12:10:00.000000Z"
             }
           } = body(conn)

    assert call_id == TestAdmissionBackend.call_id()
  end

  test "claims the token, starts once, and returns an allowed-origin WebRTC session", context do
    conn =
      :post
      |> conn(session_path(), JSON.encode!(%{}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer #{@join_token}")
      |> put_req_header("origin", @origin)
      |> Endpoint.call(context.endpoint)

    assert conn.status == 201
    assert get_resp_header(conn, "access-control-allow-origin") == [@origin]

    assert %{
             "call" => %{
               "call_id" => call_id,
               "started_at" => started_at,
               "state" => "running"
             },
             "participant" => %{
               "participant_id" => "part_test-caller",
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
           } = body(conn)

    assert call_id == TestAdmissionBackend.call_id()
    assert {:ok, %DateTime{}, 0} = DateTime.from_iso8601(started_at)
    refute conn.resp_body =~ @join_token
    refute conn.resp_body =~ "never-return-this"

    assert_receive {:test_admission_started, "rinc_test-admission", projected_at}
    assert DateTime.to_iso8601(projected_at) == started_at

    assert [
             {:claim_token, _scope},
             {:start_call, ^call_id},
             {:mark_started, ^call_id, "rinc_test-admission", ^projected_at}
           ] = await_operations(context.backend, 3)
  end

  test "keeps a live session successful when asynchronous bookkeeping fails", _context do
    backend =
      start_supervised!(
        {TestAdmissionBackend,
         api_key: @api_key, join_token: @join_token, observer: self(), projection_failure?: true},
        id: :projection_failure_backend
      )

    conn =
      :post
      |> conn(session_path(), JSON.encode!(%{}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer #{@join_token}")
      |> Endpoint.call(endpoint_options(backend))

    assert conn.status == 201
    assert_receive {:test_admission_started, "rinc_test-admission", %DateTime{}}
  end

  test "records a safe pre-live startup failure after token acceptance", _context do
    backend =
      start_supervised!(
        {TestAdmissionBackend,
         api_key: @api_key, join_token: @join_token, observer: self(), start_failure?: true},
        id: :start_failure_backend
      )

    conn =
      :post
      |> conn(session_path(), JSON.encode!(%{}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer #{@join_token}")
      |> Endpoint.call(endpoint_options(backend))

    assert conn.status == 503
    assert %{"error" => %{"code" => "call_start_failed"}} = body(conn)
    assert_receive {:test_admission_failed, :room_start_failed}
  end

  test "records live start when session setup fails after the room starts", _context do
    backend =
      start_supervised!(
        {TestAdmissionBackend,
         api_key: @api_key, join_token: @join_token, observer: self(), participant_failure?: true},
        id: :participant_failure_backend
      )

    conn =
      :post
      |> conn(session_path(), JSON.encode!(%{}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer #{@join_token}")
      |> Endpoint.call(endpoint_options(backend))

    assert conn.status == 503
    assert %{"error" => %{"code" => "session_start_failed"}} = body(conn)
    assert_receive {:test_admission_started, "rinc_test-admission", %DateTime{}}
    refute_receive {:test_admission_failed, _reason}
  end

  test "joins an eligible participant to the existing call without restarting it", _context do
    backend =
      start_supervised!(
        {TestAdmissionBackend,
         api_key: @api_key, join_token: @join_token, observer: self(), existing_call?: true},
        id: :existing_call_backend
      )

    conn =
      :post
      |> conn(session_path(), JSON.encode!(%{}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer #{@join_token}")
      |> Endpoint.call(endpoint_options(backend))

    assert conn.status == 201

    assert %{
             "call" => %{
               "started_at" => "2026-09-09T12:00:05.000000Z",
               "state" => "running"
             },
             "participant" => %{"participant_id" => "part_test-caller"},
             "session" => %{"incarnation_id" => "rinc_test-admission"}
           } = body(conn)

    refute_receive {:test_admission_started, _incarnation_id, _started_at}
    refute_receive {:test_admission_failed, _reason}

    assert [
             {:claim_token, _scope},
             {:start_call, call_id}
           ] = TestAdmissionBackend.operations(backend)

    assert call_id == TestAdmissionBackend.call_id()
  end

  test "does not let browser session input replace prepared values or visibility", context do
    conn =
      :post
      |> conn(
        session_path(),
        JSON.encode!(%{
          "initial_variables" => %{"order" => %{"id" => "browser-override"}},
          "tool_visibility" => "full"
        })
      )
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer #{@join_token}")
      |> put_req_header("origin", @origin)
      |> Endpoint.call(context.endpoint)

    assert conn.status == 400
    assert %{"error" => %{"code" => "invalid_request"}} = body(conn)
    assert TestAdmissionBackend.operations(context.backend) == []
  end

  test "does not accept a join token from a query string", context do
    conn =
      :post
      |> conn("#{session_path()}?token=#{@join_token}", JSON.encode!(%{}))
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(context.endpoint)

    assert conn.status == 401
    assert %{"error" => %{"code" => "invalid_join_token"}} = body(conn)
    assert TestAdmissionBackend.operations(context.backend) == []
  end

  test "rejects an invalid bearer join token after granting its configured origin", context do
    conn =
      :post
      |> conn(session_path(), JSON.encode!(%{}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("authorization", "Bearer vxj_invalid")
      |> put_req_header("origin", @origin)
      |> Endpoint.call(context.endpoint)

    assert conn.status == 401
    assert %{"error" => %{"code" => "invalid_join_token"}} = body(conn)
    assert get_resp_header(conn, "access-control-allow-origin") == [@origin]
    assert [{:claim_token, _scope}] = TestAdmissionBackend.operations(context.backend)
  end

  test "grants CORS only to token-based browser session admission", context do
    backend_preflight =
      :options
      |> conn(prepare_path())
      |> put_req_header("origin", @origin)
      |> put_req_header("access-control-request-method", "POST")
      |> Endpoint.call(context.endpoint)

    assert backend_preflight.status == 404
    assert get_resp_header(backend_preflight, "access-control-allow-origin") == []

    session_preflight =
      :options
      |> conn(session_path())
      |> put_req_header("origin", @origin)
      |> put_req_header("access-control-request-method", "POST")
      |> put_req_header("access-control-request-headers", "content-type,authorization")
      |> Endpoint.call(context.endpoint)

    assert session_preflight.status == 204
    assert get_resp_header(session_preflight, "access-control-allow-origin") == [@origin]

    disallowed_preflight =
      :options
      |> conn(session_path())
      |> put_req_header("origin", "https://untrusted.example.test")
      |> put_req_header("access-control-request-method", "POST")
      |> put_req_header("access-control-request-headers", "content-type,authorization")
      |> Endpoint.call(context.endpoint)

    assert get_resp_header(disallowed_preflight, "access-control-allow-origin") == []
  end

  defp endpoint_options(backend) do
    Endpoint.init(
      cors: [
        allowed_origins: [@origin],
        allowed_methods: ["POST", "PATCH", "OPTIONS"],
        allowed_headers: ["content-type", "authorization"],
        allow_credentials: false
      ],
      call_admission: [enabled: true, backend: TestAdmissionBackend.backend(backend)]
    )
  end

  defp prepare_path do
    "/api/tenants/#{TestAdmissionBackend.tenant_key()}/participants/#{TestAdmissionBackend.participant_key()}/calls"
  end

  defp session_path do
    "/api/tenants/#{TestAdmissionBackend.tenant_key()}/calls/#{TestAdmissionBackend.call_id()}/participants/#{TestAdmissionBackend.participant_key()}/sessions"
  end

  defp token_path do
    "/api/tenants/#{TestAdmissionBackend.tenant_key()}/calls/#{TestAdmissionBackend.call_id()}/participants/#{TestAdmissionBackend.participant_key()}/join-tokens"
  end

  defp body(conn), do: JSON.decode!(conn.resp_body)

  defp await_operations(backend, count) do
    _ = :sys.get_state(backend)
    operations = TestAdmissionBackend.operations(backend)

    if length(operations) >= count do
      operations
    else
      receive do
        {:test_admission_started, _incarnation_id, _started_at} ->
          await_operations(backend, count)
      after
        1_000 -> operations
      end
    end
  end
end
