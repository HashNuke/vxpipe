defmodule Vxpipe.Console.OwnOAuthCompletionTest do
  use ExUnit.Case, async: true
  alias ExMCP.Authorization.JWT
  alias Vxpipe.Console.MCPOAuthCompletion
  alias Vxpipe.MCP.OAuthCallback

  setup_all do
    rsa = :public_key.generate_key({:rsa, 2048, 65_537})
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, rsa)])
    {:ok, key} = JWT.load_key(pem)
    %{pem: pem, public: JWT.to_public_key(key)}
  end

  test "callback signs with saved key configuration and keep MCP headers away from tokens",
       data do
    owner = self()
    headers = [%{"name" => "X-Workspace", "value" => "private-workspace"}]

    secrets = %{
      "registration_method" => "own_client",
      "grant_type" => "authorization_code",
      "client_id" => "registered",
      "auth_method" => "private_key_jwt",
      "private_key" => data.pem,
      "algorithm" => "RS256",
      "key_id" => "key-1",
      "signing_algorithms" => ["RS256"],
      "token_endpoint" => "https://auth.example.test/token",
      "resource" => "https://mcp.example.test/mcp",
      "audience" => "calendar-api",
      "token_parameters" => [%{"name" => "organization", "value" => "private-org"}],
      "headers" => headers,
      "code_verifier" => String.duplicate("v", 43),
      "issuer_response_required" => true
    }

    attempt = %Vxpipe.Calls.ResolvedMCPOAuthAttempt{
      attempt: %{
        connection_id: "connection",
        generation: 1,
        issuer: "https://auth.example.test",
        resource: secrets["resource"],
        redirect_uri: "https://console.example.test/oauth/mcp/callback"
      },
      secrets: secrets
    }

    callback = %OAuthCallback{
      state: String.duplicate("s", 43),
      code: "code",
      issuer: attempt.attempt.issuer
    }

    options = [
      dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end,
      request_fun: fn _, {_url, request_headers, _type, body}, _, _ ->
        params = URI.decode_query(body)
        assert params["organization"] == "private-org"
        assert params["audience"] == "calendar-api"
        refute Map.has_key?(params, "headers")
        refute Map.has_key?(params, "private_key")

        refute Enum.any?(request_headers, fn {k, _} ->
                 String.downcase(to_string(k)) == "x-workspace"
               end)

        assert {:ok, claims} =
                 JWT.verify_and_validate(params["client_assertion"], data.public,
                   iss: "registered",
                   sub: "registered",
                   aud: secrets["token_endpoint"]
                 )

        send(owner, {:grant, params["grant_type"], claims["jti"]})

        {:ok,
         {{~c"HTTP/1.1", 200, ~c"OK"}, [],
          JSON.encode!(%{
            "access_token" => "access",
            "refresh_token" => "refresh",
            "expires_in" => 300,
            "token_type" => "Bearer"
          })}}
      end,
      connection_check: fn _, config ->
        send(owner, {:mcp_headers, config.secrets["headers"]})
        {:ok, %{server_name: "Registered MCP", catalog: []}}
      end
    ]

    assert {:ok, resolved} = MCPOAuthCompletion.complete(options, "tenant", callback, attempt)
    assert_receive {:grant, "authorization_code", _assertion_id}
    assert_receive {:mcp_headers, ^headers}
    assert resolved.secrets["private_key"] == data.pem
    refute Map.has_key?(resolved.secrets, "code_verifier")
    refute inspect(resolved) =~ data.pem
  end
end
