defmodule Vxpipe.MCP.OAuthTokenAssertionTest do
  use ExUnit.Case, async: true
  alias ExMCP.Authorization.JWT
  alias Vxpipe.MCP.{OAuthClientAssertion, OAuthTokenExchange}

  setup_all do
    key = :public_key.generate_key({:rsa, 2048, 65_537})
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, key)])

    metadata = %{
      "token_endpoint" => "https://auth.example.test/token",
      "token_endpoint_auth_methods_supported" => ["private_key_jwt"],
      "token_endpoint_auth_signing_alg_values_supported" => ["RS256"],
      "grant_types_supported" => ["client_credentials"]
    }

    {:ok, signing} =
      OAuthClientAssertion.new(
        %{
          client_id: "client",
          token_endpoint: metadata["token_endpoint"],
          private_key: pem,
          algorithm: "RS256"
        },
        metadata
      )

    {:ok, jwk} = JWT.load_key(pem)
    %{signing: signing, public: JWT.to_public_key(jwk), metadata: metadata}
  end

  test "authorization, refresh and machine grants authenticate with fresh assertions only",
       data do
    owner = self()

    options = [
      dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end,
      request_fun: fn :post, {_url, headers, _type, body}, _, _ ->
        params = URI.decode_query(body)
        assert length(Enum.to_list(URI.query_decoder(body))) == map_size(params)

        refute Enum.any?(headers, fn {k, _} ->
                 String.downcase(to_string(k)) == "authorization"
               end)

        refute Map.has_key?(params, "client_secret")
        refute Map.has_key?(params, "private_key")
        refute Map.has_key?(params, "algorithm")

        assert params["client_assertion_type"] ==
                 "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

        assert params["client_id"] == "client"
        assert params["resource"] == "https://mcp.example.test/mcp"

        assert {:ok, claims} =
                 JWT.verify_and_validate(params["client_assertion"], data.public,
                   iss: "client",
                   sub: "client",
                   aud: data.metadata["token_endpoint"]
                 )

        send(owner, {:grant, params["grant_type"], claims["jti"]})

        {:ok,
         {{~c"HTTP/1.1", 200, ~c"OK"}, [],
          JSON.encode!(%{"access_token" => "synthetic-token", "token_type" => "Bearer"})}}
      end
    ]

    base = request(data)

    code =
      Map.merge(base, %{
        code: "code",
        code_verifier: String.duplicate("v", 43),
        redirect_uri: "https://console.example.test/oauth/mcp/callback"
      })

    assert {:ok, _} = OAuthTokenExchange.exchange(code, options)
    assert_receive {:grant, "authorization_code", first}

    assert {:ok, _} =
             OAuthTokenExchange.refresh(Map.put(base, :refresh_token, "refresh"), options)

    assert_receive {:grant, "refresh_token", second}
    assert {:ok, _} = OAuthTokenExchange.client_credentials(base, data.metadata, options)
    assert_receive {:grant, "client_credentials", third}
    assert length(Enum.uniq([first, second, third])) == 3
  end

  test "rejects mismatched signing identity and inactive credential fields before DNS", data do
    owner = self()

    options = [
      dns_resolver: fn _, _ ->
        send(owner, :unexpected_signing_dns)
        {:error, :fixture_stopped}
      end
    ]

    for input <- [
          Map.put(request(data), :client_id, "other"),
          Map.put(request(data), :token_endpoint, "https://other.example.test/token"),
          Map.put(request(data), :client_secret, "forbidden"),
          Map.put(request(data), :client_secret_expires_at, 0),
          Map.put(request(data), :client_assertion, %{}),
          Map.put(request(data), :auth_method, :none),
          request(data)
          |> Map.put(:auth_method, :client_secret_post)
          |> Map.put(:client_secret, "secret")
        ] do
      assert {:error, _} =
               OAuthTokenExchange.refresh(Map.put(input, :refresh_token, "refresh"), options)

      refute_received :unexpected_signing_dns
    end

    assert {:error, _} =
             OAuthTokenExchange.client_credentials(
               request(data),
               Map.put(data.metadata, "token_endpoint_auth_signing_alg_values_supported", [
                 "ES256"
               ]),
               options
             )

    refute_received :unexpected_signing_dns
  end

  defp request(data),
    do: %{
      token_endpoint: data.metadata["token_endpoint"],
      client_id: "client",
      resource: "https://mcp.example.test/mcp",
      auth_method: :private_key_jwt,
      client_assertion: data.signing
    }
end
