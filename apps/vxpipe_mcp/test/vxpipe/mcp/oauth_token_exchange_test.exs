defmodule Vxpipe.MCP.OAuthTokenExchangeTest do
  use ExUnit.Case, async: true
  alias Vxpipe.MCP.OAuthTokenExchange

  defp request do
    %{
      token_endpoint: "https://auth.example.test/token",
      client_id: "client",
      auth_method: :none,
      code: "private-code",
      code_verifier: String.duplicate("v", 43),
      redirect_uri: "https://console.example.test/oauth/mcp/callback",
      resource: "https://mcp.example.test/mcp"
    }
  end

  defp options(fun),
    do: [dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end, request_fun: fun]

  defp response(status, body),
    do: {:ok, {{~c"HTTP/1.1", status, ~c"Result"}, [], JSON.encode!(body)}}

  test "all confidential token grants enforce expiry locally without sending it as a form field" do
    owner = self()

    opts =
      options(fn _, {_, _, _, body}, _, _ ->
        send(owner, {:token_body, URI.decode_query(body)})
        response(200, %{"access_token" => "access", "token_type" => "Bearer"})
      end)

    code =
      Map.merge(request(), %{auth_method: :client_secret_post, client_secret: "private-secret"})

    refresh =
      code
      |> Map.take([:token_endpoint, :client_id, :auth_method, :client_secret, :resource])
      |> Map.put(:refresh_token, "refresh")

    machine = Map.delete(refresh, :refresh_token)

    metadata = %{
      "token_endpoint" => machine.token_endpoint,
      "grant_types_supported" => ["client_credentials"],
      "token_endpoint_auth_methods_supported" => ["client_secret_post"]
    }

    grants = [
      {code, fn req -> OAuthTokenExchange.exchange(req, opts) end, :invalid_oauth_token_request},
      {refresh, fn req -> OAuthTokenExchange.refresh(req, opts) end,
       :invalid_oauth_token_request},
      {machine, fn req -> OAuthTokenExchange.client_credentials(req, metadata, opts) end,
       :invalid_oauth_client_credentials}
    ]

    for {input, exchange, error} <- grants do
      for expiry <- [0, System.os_time(:second) + 3600] do
        assert {:ok, _} = exchange.(Map.put(input, :client_secret_expires_at, expiry))
        assert_receive {:token_body, body}
        refute Map.has_key?(body, "client_secret_expires_at")
      end

      for expiry <- [1, -1, "0", System.os_time(:second)] do
        assert {:error, ^error} = exchange.(Map.put(input, :client_secret_expires_at, expiry))
        refute_received {:token_body, _}
      end
    end
  end

  test "Own-client literal token parameters are sent for each grant without overriding fixed fields" do
    owner = self()

    opts =
      options(fn _, {_, _, _, body}, _, _ ->
        send(owner, {:parameters, URI.decode_query(body)})
        response(200, %{"access_token" => "access", "token_type" => "Bearer"})
      end)

    code =
      Map.merge(request(), %{
        parameters: [%{"name" => "organization", "value" => "tenant-label"}],
        audience: "provider-api",
        auth_method: :client_secret_post,
        client_secret: "secret"
      })

    refresh =
      code
      |> Map.drop([:code, :code_verifier, :redirect_uri])
      |> Map.put(:refresh_token, "refresh")

    machine = Map.delete(refresh, :refresh_token)

    metadata = %{
      "token_endpoint" => machine.token_endpoint,
      "grant_types_supported" => ["client_credentials"],
      "token_endpoint_auth_methods_supported" => ["client_secret_post"]
    }

    for {input, call} <- [
          {code, &OAuthTokenExchange.exchange(&1, opts)},
          {refresh, &OAuthTokenExchange.refresh(&1, opts)},
          {machine, &OAuthTokenExchange.client_credentials(&1, metadata, opts)}
        ] do
      assert {:ok, _} = call.(input)
      assert_receive {:parameters, body}
      assert body["organization"] == "tenant-label"
      assert body["audience"] == "provider-api"
      assert body["resource"] == input.resource

      for field <- ~w(grant_type code client_id client_secret client_assertion resource audience) do
        assert {:error, _} =
                 call.(Map.put(input, :parameters, [%{"name" => field, "value" => "override"}]))

        refute_received {:parameters, _}
      end
    end
  end

  test "token endpoint query cannot hide managed fields or duplicate token parameters" do
    owner = self()

    opts =
      options(fn _, _, _, _ ->
        send(owner, :unexpected_parameter_http)
        response(200, %{"access_token" => "access", "token_type" => "Bearer"})
      end)

    for query <- [
          "grant_type=password",
          "request_uri=https%3A%2F%2Fexample.test%2Fr",
          "organization=one&organization=two"
        ] do
      input = Map.put(request(), :token_endpoint, "https://auth.example.test/token?" <> query)
      assert {:error, _} = OAuthTokenExchange.exchange(input, opts)
    end

    input =
      Map.merge(request(), %{
        token_endpoint: "https://auth.example.test/token?organization=one",
        parameters: [%{"name" => "organization", "value" => "two"}]
      })

    assert {:error, _} = OAuthTokenExchange.exchange(input, opts)
    refute_received :unexpected_parameter_http
  end

  test "client credentials uses supported confidential authentication and fixed resource fields" do
    owner = self()

    for method <- [:client_secret_basic, :client_secret_post] do
      request = %{
        token_endpoint: "https://auth.example.test/token",
        client_id: "client",
        client_secret: "private-secret",
        auth_method: method,
        resource: "https://mcp.example.test/mcp",
        scope: "tools:read tools:write"
      }

      metadata = %{
        "token_endpoint" => request.token_endpoint,
        "grant_types_supported" => ["client_credentials"],
        "token_endpoint_auth_methods_supported" => [Atom.to_string(method)]
      }

      opts =
        options(fn :post, {_url, headers, _type, body}, _, _ ->
          send(owner, {:client_credentials, headers, URI.decode_query(body)})

          response(200, %{
            "access_token" => "machine-token",
            "token_type" => "Bearer",
            "expires_in" => 300,
            "refresh_token" => "unused-refresh"
          })
        end)

      assert {:ok, token} = OAuthTokenExchange.client_credentials(request, metadata, opts)
      assert token.access_token == "machine-token"
      assert token.refresh_token == nil
      refute inspect(token) =~ "machine-token"
      assert_receive {:client_credentials, headers, body}
      assert body["grant_type"] == "client_credentials"
      assert body["resource"] == request.resource
      assert body["scope"] == request.scope
      refute Map.has_key?(body, "code")
      refute Map.has_key?(body, "redirect_uri")

      if method == :client_secret_basic do
        assert Enum.any?(headers, fn {name, value} ->
                 String.downcase(to_string(name)) == "authorization" and
                   String.starts_with?(to_string(value), "Basic ")
               end)

        refute Map.has_key?(body, "client_secret")
      else
        assert body["client_secret"] == "private-secret"
      end
    end
  end

  test "client credentials rejects public clients, unsupported grants and inactive overrides before HTTP" do
    request = %{
      token_endpoint: "https://auth.example.test/token",
      client_id: "client",
      client_secret: "private-secret",
      auth_method: :client_secret_post,
      resource: "https://mcp.example.test/mcp"
    }

    metadata = %{
      "token_endpoint" => request.token_endpoint,
      "grant_types_supported" => ["client_credentials"],
      "token_endpoint_auth_methods_supported" => ["client_secret_post"]
    }

    opts = options(fn _, _, _, _ -> flunk("invalid client credentials request reached HTTP") end)

    for {input, server} <- [
          {Map.put(request, :auth_method, :none), metadata},
          {request, Map.put(metadata, "grant_types_supported", ["authorization_code"])},
          {request, Map.put(metadata, "token_endpoint", "https://other.example/token")},
          {Map.put(request, :grant_type, "password"), metadata},
          {Map.put(request, :redirect_uri, "https://console.example/callback"), metadata},
          {Map.put(request, :scope, "bad\nscope"), metadata}
        ] do
      assert {:error, _} = OAuthTokenExchange.client_credentials(input, server, opts)
    end
  end

  test "code exchange pins destination and sends fixed PKCE, callback and resource once" do
    owner = self()

    opts =
      options(fn :post, {url, _headers, _type, body}, http, _ ->
        send(owner, {:request, to_string(url), URI.decode_query(body), http})

        response(200, %{
          "access_token" => "private-token",
          "token_type" => "Bearer",
          "expires_in" => 300,
          "refresh_token" => "refresh"
        })
      end)

    assert {:ok, result} = OAuthTokenExchange.exchange(request(), opts)
    assert result.access_token == "private-token"
    refute inspect(result) =~ "private-token"
    assert_receive {:request, "https://93.184.216.34/token", body, http}

    assert body == %{
             "grant_type" => "authorization_code",
             "code" => "private-code",
             "code_verifier" => String.duplicate("v", 43),
             "client_id" => "client",
             "redirect_uri" => request().redirect_uri,
             "resource" => request().resource
           }

    assert http[:autoredirect] == false
    refute_received {:request, _, _, _}
  end

  test "refresh sends only saved resource/client and refresh credentials" do
    owner = self()

    refresh =
      request()
      |> Map.drop([:code, :code_verifier, :redirect_uri])
      |> Map.put(:refresh_token, "old-refresh")

    opts =
      options(fn :post, {_, _, _, body}, _, _ ->
        send(owner, {:refresh_body, URI.decode_query(body)})

        response(200, %{
          "access_token" => "rotated",
          "token_type" => "Bearer",
          "refresh_token" => "new-refresh"
        })
      end)

    assert {:ok, token} = OAuthTokenExchange.refresh(refresh, opts)
    assert token.refresh_token == "new-refresh"
    assert_receive {:refresh_body, body}

    assert body == %{
             "grant_type" => "refresh_token",
             "refresh_token" => "old-refresh",
             "client_id" => "client",
             "resource" => request().resource
           }

    assert {:error, :invalid_oauth_token_request} =
             OAuthTokenExchange.refresh(Map.put(refresh, :code, "unexpected"), opts)

    refute_received {:refresh_body, _}
  end

  test "errors are redacted and redirects and ambiguous responses are never retried" do
    owner = self()

    for result <- [
          response(400, %{"error" => "invalid_grant", "error_description" => "private"}),
          response(302, %{}),
          {:error, {:timeout, "private"}}
        ] do
      opts =
        options(fn _, _, _, _ ->
          send(owner, :request)
          result
        end)

      assert {:error, reason} = OAuthTokenExchange.exchange(request(), opts)
      assert reason in [:oauth_grant_rejected, :oauth_token_exchange_failed]
      assert_receive :request
      refute_received :request
    end
  end

  test "invalid inputs and private destinations never send codes" do
    owner = self()

    opts =
      options(fn _, _, _, _ ->
        send(owner, :request)
        response(200, %{})
      end)

    for invalid <- [
          %{request() | auth_method: :unknown},
          %{request() | code_verifier: "short"},
          Map.put(request(), :grant_type, "password"),
          %{request() | token_endpoint: "http://127.0.0.1/token"}
        ] do
      assert {:error, :invalid_oauth_token_request} = OAuthTokenExchange.exchange(invalid, opts)
    end

    private = Keyword.put(opts, :dns_resolver, fn _, _ -> {:ok, [{127, 0, 0, 1}]} end)

    assert {:error, :oauth_token_exchange_failed} =
             OAuthTokenExchange.exchange(request(), private)

    refute_received :request
  end

  test "rejects malformed and unsupported token responses" do
    for token <- [
          %{"access_token" => ""},
          %{"access_token" => "token"},
          %{"access_token" => "token", "token_type" => "DPoP"},
          %{"access_token" => "token", "token_type" => "Bearer", "expires_in" => -1}
        ] do
      assert {:error, :invalid_oauth_token_response} =
               OAuthTokenExchange.exchange(
                 request(),
                 options(fn _, _, _, _ -> response(200, token) end)
               )
    end
  end

  test "raw token responses must be usable by the Bearer transport and have valid scope syntax" do
    base = %{"access_token" => "token", "token_type" => "Bearer"}

    invalid =
      Enum.map(
        ["bad\r\ntoken", "token value", "token:bad", "tøkén", String.duplicate("t", 8193)],
        &Map.put(base, "access_token", &1)
      ) ++
        Enum.map(
          ["", "tools:read\nadmin", "tools:read  tools:write", "bad\\scope", "é"],
          &Map.put(base, "scope", &1)
        )

    for body <- invalid do
      assert {:error, :invalid_oauth_token_response} =
               OAuthTokenExchange.exchange(
                 request(),
                 options(fn _, _, _, _ -> response(200, body) end)
               )
    end

    for token <- ["a-._~+/==", String.duplicate("t", 8192)] do
      body = %{base | "access_token" => token, "token_type" => "bEaReR"}
      body = Map.put(body, "scope", "tools:read tools:write")

      assert {:ok, result} =
               OAuthTokenExchange.exchange(
                 request(),
                 options(fn _, _, _, _ -> response(200, body) end)
               )

      assert result.access_token == token
    end
  end
end
