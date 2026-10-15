defmodule Vxpipe.Gateway.MCP.EndpointTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Calls.{InstallationOperator, Principal}
  alias Vxpipe.Gateway.MCP.{Admission, Endpoint}

  @version "2025-11-25"
  @secret "vxak_local-synthetic-key"

  setup do
    actor = %Principal{
      tenant_key: "AAAAAAAAAAAAAAAA",
      api_key_id: "key-one",
      scopes: MapSet.new([:calls])
    }

    backend = start_supervised!({Agent, fn -> %{result: {:ok, actor}, calls: 0} end})
    admission = start_supervised!({Admission, name: nil, max_concurrency: 1})

    options = [
      enabled: true,
      allowed_hosts: ["localhost"],
      admission: admission,
      authentication: {__MODULE__, backend}
    ]

    %{options: options, backend: backend, admission: admission}
  end

  test "disabled endpoint is unavailable without examining credentials", context do
    response = call(:post, initialize(), Keyword.put(context.options, :enabled, false))
    assert response.status == 404
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert Agent.get(context.backend, & &1.calls) == 0
  end

  test "initializes tools-only sessions and reauthenticates subsequent discovery", context do
    initialized = call(:post, initialize(), context.options, @secret)
    assert initialized.status == 200

    assert %{"result" => %{"protocolVersion" => @version, "capabilities" => %{"tools" => %{}}}} =
             JSON.decode!(initialized.resp_body)

    assert [session_id] = get_resp_header(initialized, "mcp-session-id")
    on_exit(fn -> ExMCP.SessionManager.terminate_session(session_id) end)

    tools = call(:post, rpc("tools/list", 2), context.options, @secret, session_id)
    assert tools.status == 200

    assert Enum.map(JSON.decode!(tools.resp_body)["result"]["tools"], & &1["name"]) ==
             ["list_tenants", "get_tenant", "create_call", "create_join_token"]

    assert Agent.get(context.backend, & &1.calls) == 2
    assert get_req_header(tools, "authorization") == []
    refute inspect(tools.assigns) =~ @secret

    Agent.update(context.backend, &%{&1 | result: {:error, :invalid_api_key}})
    revoked = call(:post, rpc("ping", 3), context.options, @secret, session_id)
    assert revoked.status == 401

    assert get_resp_header(revoked, "www-authenticate") ==
             [~s(Bearer realm="vxpipe", error="invalid_token")]
  end

  test "credentials are required on every HTTP method, with no alternate credential source",
       context do
    for method <- [:post, :get, :delete, :options] do
      missing = call(method, initialize(), context.options)
      assert missing.status == 401
      assert get_resp_header(missing, "www-authenticate") == [~s(Bearer realm="vxpipe")]
    end

    conn =
      conn(
        :post,
        "https://localhost/mcp?api_key=#{@secret}",
        JSON.encode!(Map.put(initialize(), "api_key", @secret))
      )
      |> put_req_header("content-type", "application/json")
      |> put_req_cookie("vxpipe_user_session", @secret)
      |> Endpoint.call(Endpoint.init(context.options))

    assert conn.status == 401
    assert Agent.get(context.backend, & &1.calls) == 0
  end

  test "an existing session never substitutes for credentials on notifications or tools",
       context do
    initialized = call(:post, initialize(), context.options, @secret)
    [session] = get_resp_header(initialized, "mcp-session-id")
    on_exit(fn -> ExMCP.SessionManager.terminate_session(session) end)

    requests = [
      rpc("notifications/initialized", 2) |> Map.delete("id"),
      rpc("tools/list", 3),
      rpc("tools/call", 4, %{"name" => "list_tenants", "arguments" => %{}})
    ]

    for request <- requests, source <- [:none, :cookie, :query, :body] do
      url = "https://localhost/mcp" <> if(source == :query, do: "?api_key=#{@secret}", else: "")
      body = if source == :body, do: Map.put(request, "api_key", @secret), else: request

      conn =
        conn(:post, url, JSON.encode!(body))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("mcp-protocol-version", @version)
        |> put_req_header("mcp-session-id", session)

      conn =
        if source == :cookie, do: put_req_cookie(conn, "vxpipe_user_session", @secret), else: conn

      response = Endpoint.call(conn, Endpoint.init(context.options))
      assert response.status == 401
      assert get_resp_header(response, "www-authenticate") == [~s(Bearer realm="vxpipe")]
    end

    assert Agent.get(context.backend, & &1.calls) == 1
    assert call(:post, rpc("tools/list", 5), context.options, @secret, session).status == 200
  end

  test "malformed or multiple Authorization headers never reach authentication", context do
    for value <- [
          "Basic abc",
          "Bearer",
          "Bearer ",
          "Bearer a,b",
          "Bearer a b",
          "Bearer " <> String.duplicate("x", 257)
        ] do
      response =
        conn(:post, "https://localhost/mcp", JSON.encode!(initialize()))
        |> put_req_header("authorization", value)
        |> Endpoint.call(Endpoint.init(context.options))

      assert response.status == 400
    end

    conn = conn(:post, "https://localhost/mcp", JSON.encode!(initialize()))

    conn = %{
      conn
      | req_headers: [
          {"authorization", "Bearer #{@secret}"},
          {"authorization", "Bearer #{@secret}"}
        ]
    }

    assert Endpoint.call(conn, Endpoint.init(context.options)).status == 400
    assert Agent.get(context.backend, & &1.calls) == 0
  end

  test "authentication outages fail closed and legacy authority cannot become a platform key",
       context do
    Agent.update(context.backend, &%{&1 | result: {:error, :repository_unavailable}})
    assert call(:post, initialize(), context.options, @secret).status == 503

    legacy = %InstallationOperator{
      grant: :installation_operator,
      api_key_id: "legacy",
      credential_kind: :legacy_operator_api_key
    }

    Agent.update(context.backend, &%{&1 | result: {:ok, legacy}})
    assert call(:post, initialize(), context.options, @secret).status == 401
  end

  test "raised or exited authentication failures cannot leak private backend details", context do
    for failure <- [:raise, :exit] do
      options = Keyword.put(context.options, :authentication, {__MODULE__, failure})

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          response = call(:post, initialize(), options, @secret)
          assert response.status == 503
          refute response.resp_body =~ "private-backend-detail"
          refute response.resp_body =~ @secret
        end)

      refute log =~ "private-backend-detail"
      refute log =~ @secret
    end
  end

  test "host, origin and transport restrictions precede authentication", context do
    for {url, headers, status} <- [
          {"https://evil.example/mcp", [], 421},
          {"http://localhost/mcp", [], 403},
          {"https://localhost/mcp", [{"origin", "https://evil.example"}], 403}
        ] do
      conn = conn(:post, url, JSON.encode!(initialize()))

      conn =
        Enum.reduce(headers, conn, fn {key, value}, conn -> put_req_header(conn, key, value) end)

      assert Endpoint.call(conn, Endpoint.init(context.options)).status == status
    end

    assert Agent.get(context.backend, & &1.calls) == 0

    local =
      conn(:get, "http://localhost/mcp")
      |> put_req_header("authorization", "Bearer #{@secret}")
      |> Endpoint.call(Endpoint.init(Keyword.put(context.options, :allow_loopback_http, true)))

    assert local.status == 405
  end

  test "authenticated GET cannot open a stream and unrelated methods cannot reach handlers",
       context do
    get = call(:get, nil, context.options, @secret)
    assert get.status == 405
    assert get_resp_header(get, "allow") == ["POST, DELETE"]

    for method <- [
          "logging/setLevel",
          "resources/list",
          "server/discover",
          "subscriptions/listen"
        ] do
      rejected = call(:post, rpc(method, 1), context.options, @secret)
      assert %{"error" => %{"code" => -32601}} = JSON.decode!(rejected.resp_body)
      assert get_resp_header(rejected, "mcp-session-id") == []
    end
  end

  test "unsupported protocol profiles and oversized bodies are rejected before session allocation",
       context do
    request = put_in(initialize(), ["params", "protocolVersion"], "2026-07-28")
    rejected = call(:post, request, context.options, @secret)
    assert rejected.status == 400
    assert get_resp_header(rejected, "mcp-session-id") == []

    oversized = call(:post, initialize(), Keyword.put(context.options, :body_limit, 16), @secret)
    assert oversized.status == 413
  end

  test "unknown notifications have no JSON-RPC response", context do
    request = rpc("notifications/unknown", 1) |> Map.delete("id")
    response = call(:post, request, context.options, @secret)
    assert response.status == 202
    assert response.resp_body == ""
    assert get_resp_header(response, "mcp-session-id") == []
  end

  test "oversized request IDs cannot allocate sessions or enter existing session history",
       context do
    initialized = call(:post, initialize(), context.options, @secret)
    [session_id] = get_resp_header(initialized, "mcp-session-id")
    on_exit(fn -> ExMCP.SessionManager.terminate_session(session_id) end)

    for id <- [String.duplicate("x", 257), 9_007_199_254_740_992],
        {request, session} <- [
          {initialize(), nil},
          {rpc("ping", 2), session_id},
          {%{"jsonrpc" => "2.0", "result" => %{}}, session_id}
        ] do
      response = call(:post, Map.put(request, "id", id), context.options, @secret, session)
      assert response.status == 400
      assert %{"id" => nil, "error" => %{"code" => -32600}} = JSON.decode!(response.resp_body)
      assert get_resp_header(response, "mcp-session-id") == []
    end

    assert call(:post, rpc("ping", "still-valid"), context.options, @secret, session_id).status ==
             200
  end

  test "concurrency admission rejects excess requests and releases capacity", context do
    assert {:ok, lease} = Admission.acquire(context.admission)
    assert call(:get, nil, context.options, @secret).status == 503
    assert Agent.get(context.backend, & &1.calls) == 0
    assert :ok = Admission.release(context.admission, lease)
    assert call(:get, nil, context.options, @secret).status == 405
    assert call(:get, nil, context.options, @secret).status == 405
  end

  def authenticate(:raise, _secret), do: raise("private-backend-detail")
  def authenticate(:exit, _secret), do: exit({:private, "private-backend-detail"})

  def authenticate(backend, secret) do
    Agent.get_and_update(backend, fn state ->
      result = if secret == @secret, do: state.result, else: {:error, :invalid_api_key}
      {result, %{state | calls: state.calls + 1}}
    end)
  end

  defp initialize do
    rpc("initialize", 1, %{
      "protocolVersion" => @version,
      "capabilities" => %{},
      "clientInfo" => %{"name" => "local-test", "version" => "1"}
    })
  end

  defp rpc(method, id, params \\ %{}),
    do: %{"jsonrpc" => "2.0", "method" => method, "params" => params, "id" => id}

  defp call(method, body, options, secret \\ nil, session_id \\ nil) do
    conn = conn(method, "https://localhost/mcp", if(body, do: JSON.encode!(body), else: ""))
    conn = put_req_header(conn, "content-type", "application/json")
    conn = put_req_header(conn, "mcp-protocol-version", @version)
    conn = if secret, do: put_req_header(conn, "authorization", "Bearer #{secret}"), else: conn
    conn = if session_id, do: put_req_header(conn, "mcp-session-id", session_id), else: conn
    Endpoint.call(conn, Endpoint.init(options))
  end
end
