defmodule Vxpipe.Gateway.OAuth.EndpointTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Gateway.HTTP.{Endpoint, Mount}
  alias Vxpipe.Gateway.Test.OAuthBackend

  @issuer "https://auth.example.test"
  @resource "https://api.example.test/gateway/mcp"

  test "public metadata uses trusted issuer and exact prefixed resource" do
    endpoint = Endpoint.init(oauth: options())
    resource = request(endpoint, :get, "/.well-known/oauth-protected-resource/gateway/mcp")
    assert resource.status == 200

    assert decode(resource) == %{
             "resource" => @resource,
             "authorization_servers" => [@issuer],
             "scopes_supported" => ["mcp"],
             "bearer_methods_supported" => ["header"]
           }

    server = request(endpoint, :get, "/.well-known/oauth-authorization-server") |> decode()
    assert server["issuer"] == @issuer
    assert server["authorization_endpoint"] == @issuer <> "/oauth/authorize"
    assert server["token_endpoint"] == @issuer <> "/oauth/token"
    assert server["registration_endpoint"] == @issuer <> "/oauth/register"
    assert server["code_challenge_methods_supported"] == ["S256"]
    assert server["token_endpoint_auth_methods_supported"] == ["none"]
    assert server["grant_types_supported"] == ["authorization_code", "refresh_token"]
    refute Map.has_key?(server, "client_id_metadata_document_supported")
    refute_received {:oauth_rate_limit, _, _}
  end

  test "prefixed mount claims metadata outside the prefix and leaves browser authorization alone" do
    mount = Mount.init(path_prefix: "/gateway", oauth: options())

    response =
      conn(:get, "https://api.example.test/.well-known/oauth-protected-resource/gateway/mcp")
      |> Mount.call(mount)

    assert response.status == 200
    assert response.halted
    authorization = conn(:get, @issuer <> "/oauth/authorize") |> Mount.call(mount)
    refute authorization.halted
    assert authorization.state == :unset

    prefixed = Mount.init(path_prefix: "/gateway", oauth: options(issuer: @issuer <> "/identity"))

    response =
      conn(:get, @issuer <> "/.well-known/oauth-authorization-server/identity")
      |> Mount.call(prefixed)

    assert response.status == 200
    assert decode(response)["token_endpoint"] == @issuer <> "/identity/oauth/token"

    assert request(
             Endpoint.init(oauth: options(issuer: @issuer <> "/identity")),
             :post,
             "/identity/oauth/token",
             "grant_type=refresh_token",
             "application/x-www-form-urlencoded"
           ).status == 200
  end

  test "disabled OAuth stays unclaimed and enabled invalid runtime URLs fail closed" do
    mount = Mount.init(oauth: [])

    refute (conn(:get, @issuer <> "/.well-known/oauth-authorization-server")
            |> Mount.call(mount)).halted

    assert request(Endpoint.init([]), :get, "/.well-known/oauth-authorization-server").status ==
             404

    for invalid <- [
          "http://external.test",
          "https://user:secret@auth.example.test",
          "https://auth.example.test?x=1",
          "https://auth.example.test/#fragment",
          "/relative",
          "https://auth.example.test/a/../b"
        ] do
      assert_raise ArgumentError, fn -> Endpoint.init(oauth: options(issuer: invalid)) end
    end
  end

  test "register token and revoke pass only body params and canonical resource to the backend" do
    endpoint = Endpoint.init(oauth: options())

    registration =
      request(
        endpoint,
        :post,
        "/oauth/register",
        JSON.encode!(%{client_name: "Example", redirect_uris: ["http://127.0.0.1:4321/cb"]}),
        "application/json"
      )

    assert registration.status == 201
    assert decode(registration)["client_id"]
    assert_received {:oauth_register, %{"client_name" => "Example"}}
    assert_received {:oauth_rate_limit, :register, "127.0.0.1"}

    token =
      request(
        endpoint,
        :post,
        "/oauth/token",
        "grant_type=refresh_token&refresh_token=synthetic",
        "application/x-www-form-urlencoded"
      )

    assert token.status == 200
    assert decode(token)["access_token"] == "test-token"
    assert get_resp_header(token, "cache-control") == ["no-store"]
    assert get_resp_header(token, "pragma") == ["no-cache"]

    assert_received {:oauth_exchange,
                     %{"grant_type" => "refresh_token", "refresh_token" => "synthetic"},
                     @resource}

    revoked =
      request(
        endpoint,
        :post,
        "/oauth/revoke",
        "token=unknown",
        "application/x-www-form-urlencoded"
      )

    assert revoked.status == 200
    assert revoked.resp_body == ""
    assert_received {:oauth_revoke, %{"token" => "unknown"}, @resource}
  end

  test "duplicate decoded form fields, query credentials and authorization headers are rejected" do
    endpoint = Endpoint.init(oauth: options())

    for body <- [
          "client_id=one&client_id=two",
          "client_id=one&client%5fid=two",
          "code=%ZZ",
          "code=%"
        ] do
      assert request(endpoint, :post, "/oauth/token", body, "application/x-www-form-urlencoded").status ==
               400
    end

    assert request(
             endpoint,
             :post,
             "/oauth/token?code=secret",
             "code=secret",
             "application/x-www-form-urlencoded"
           ).status == 400

    authorized =
      conn(:post, @issuer <> "/oauth/token", "code=secret")
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("authorization", "Bearer secret")
      |> Endpoint.call(endpoint)

    assert authorized.status == 400
    refute_received {:oauth_exchange, _, _}
  end

  test "registration rejects duplicate JSON keys before registration" do
    endpoint = Endpoint.init(oauth: options())

    response =
      request(
        endpoint,
        :post,
        "/oauth/register",
        ~s({"client_name":"one","client_name":"two"}),
        "application/json"
      )

    assert response.status == 400
    refute_received {:oauth_register, _}
  end

  test "body format and size are bounded before backend processing" do
    endpoint = Endpoint.init(oauth: options())

    for {path, body, content_type, status} <- [
          {"/oauth/register", "[]", "application/json", 400},
          {"/oauth/register", "{", "application/json", 400},
          {"/oauth/token", "code=one", "application/json", 415},
          {"/oauth/register", String.duplicate("x", 16_385), "application/json", 413},
          {"/oauth/token", String.duplicate("x", 16_385), "application/x-www-form-urlencoded",
           413}
        ] do
      assert request(endpoint, :post, path, body, content_type).status == status
    end

    refute_received {:oauth_register, _}
    refute_received {:oauth_exchange, _, _}
  end

  test "host scheme origin method and CORS boundaries apply before public operations" do
    endpoint = Endpoint.init(oauth: options())

    assert (conn(:get, "https://evil.test/.well-known/oauth-authorization-server")
            |> Endpoint.call(endpoint)).status == 421

    assert (conn(:get, "http://auth.example.test/.well-known/oauth-authorization-server")
            |> Endpoint.call(endpoint)).status == 403

    assert request(endpoint, :get, "/oauth/token").status == 405

    for origin <- ["https://evil.test", "null"] do
      conn =
        conn(:get, @issuer <> "/.well-known/oauth-authorization-server")
        |> put_req_header("origin", origin)
        |> Endpoint.call(endpoint)

      assert conn.status == 403
      assert get_resp_header(conn, "access-control-allow-origin") == []
    end

    preflight =
      conn(:options, @issuer <> "/oauth/token")
      |> put_req_header("origin", "https://client.test")
      |> put_req_header("access-control-request-method", "POST")
      |> put_req_header("access-control-request-headers", "content-type")
      |> Endpoint.call(endpoint)

    assert preflight.status == 204
    assert get_resp_header(preflight, "access-control-allow-origin") == ["https://client.test"]
    assert get_resp_header(preflight, "access-control-allow-credentials") == []
    refute_received {:oauth_exchange, _, _}
  end

  test "rate limits and unexpected backend failures expose only safe OAuth errors" do
    endpoint = Endpoint.init(oauth: options())
    Process.put({OAuthBackend, :rate_limit}, {:error, :rate_limited})

    limited =
      request(endpoint, :post, "/oauth/token", "code=secret", "application/x-www-form-urlencoded")

    assert limited.status == 429
    assert get_resp_header(limited, "retry-after") == ["60"]
    refute_received {:oauth_exchange, _, _}
    Process.delete({OAuthBackend, :rate_limit})

    for failure <- [:raise, :exit, {:error, "credential-sentinel"}, {:error, :unavailable}] do
      Process.put({OAuthBackend, :result}, failure)

      response =
        request(
          endpoint,
          :post,
          "/oauth/token",
          "code=secret",
          "application/x-www-form-urlencoded"
        )

      assert response.status == 503
      assert decode(response) == %{"error" => "temporarily_unavailable"}
      refute response.resp_body =~ "credential-sentinel"
    end

    Process.put({OAuthBackend, :result}, {:error, :invalid_grant})

    assert request(
             endpoint,
             :post,
             "/oauth/token",
             "code=secret",
             "application/x-www-form-urlencoded"
           )
           |> decode() == %{"error" => "invalid_grant"}
  end

  test "body read timeout fails before exchange without exposing transport details" do
    endpoint = Endpoint.init(oauth: options())

    request =
      conn(:post, @issuer <> "/oauth/token", "code=synthetic")
      |> put_req_header("content-type", "application/x-www-form-urlencoded")

    {_adapter, payload} = request.adapter

    response =
      %{request | adapter: {Vxpipe.Gateway.Test.OAuthTimeoutAdapter, payload}}
      |> Endpoint.call(endpoint)

    assert response.status == 408
    assert decode(response) == %{"error" => "invalid_request"}
    refute_received {:oauth_exchange, _, _}
  end

  test "browser cookies do not authorize token requests and forwarded IP cannot select quota bucket" do
    endpoint = Endpoint.init(oauth: options())

    response =
      conn(:post, @issuer <> "/oauth/token", "code=synthetic")
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("cookie", "_vxpipe_key=synthetic-session")
      |> put_req_header("x-forwarded-for", "203.0.113.1")
      |> Endpoint.call(endpoint)

    assert response.status == 200
    assert_received {:oauth_rate_limit, :token, "127.0.0.1"}
    assert_received {:oauth_exchange, %{"code" => "synthetic"}, @resource}
  end

  test "configured address resolvers must return a canonical literal address" do
    resolver = fn _conn -> "2001:db8::7" end
    endpoint = Endpoint.init(oauth: options(client_address_resolver: resolver))

    assert request(
             endpoint,
             :post,
             "/oauth/token",
             "code=synthetic",
             "application/x-www-form-urlencoded"
           ).status == 200

    assert_received {:oauth_rate_limit, :token, "2001:db8::7"}
  end

  test "invalid or failing configured address resolvers fail closed before rate limiting" do
    for resolver <- [
          fn _ -> "2001:0db8:0:0:0:0:0:7" end,
          fn _ -> "not-an-address" end,
          fn _ -> <<255>> end,
          fn _ -> nil end,
          fn _ -> raise "private-address-sentinel" end,
          fn _ -> exit(:resolver_failed) end,
          :invalid
        ] do
      endpoint = Endpoint.init(oauth: options(client_address_resolver: resolver))

      response =
        request(
          endpoint,
          :post,
          "/oauth/token",
          "code=synthetic",
          "application/x-www-form-urlencoded"
        )

      assert response.status == 503
      assert decode(response) == %{"error" => "temporarily_unavailable"}
    end

    refute_received {:oauth_rate_limit, _, _}
    refute_received {:oauth_exchange, _, _}
  end

  defp options(overrides \\ []) do
    Keyword.merge(
      [
        enabled: true,
        issuer: @issuer,
        resource: @resource,
        allowed_hosts: ["auth.example.test", "api.example.test"],
        allowed_origins: ["https://client.test"],
        backend: OAuthBackend
      ],
      overrides
    )
  end

  defp request(endpoint, method, path, body \\ "", type \\ nil) do
    conn = conn(method, @issuer <> path, body)
    conn = if type, do: put_req_header(conn, "content-type", type), else: conn
    Endpoint.call(conn, endpoint)
  end

  defp decode(conn), do: JSON.decode!(conn.resp_body)
end
