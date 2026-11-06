defmodule Vxpipe.MCP.OAuthMetadataTest do
  use ExUnit.Case, async: true
  alias Vxpipe.MCP.OAuthMetadata

  test "issuer paths use OAuth insertion, OIDC insertion, then OIDC appending" do
    owner = self()
    issuer = "https://auth.example.test/tenant"

    options =
      options(fn uri, _address, _options ->
        send(owner, {:request, URI.to_string(uri)})

        if uri.path == "/tenant/.well-known/openid-configuration",
          do: response(metadata(issuer)),
          else: {:ok, %{status: 404, headers: [], body: ""}}
      end)

    assert {:ok, result} = OAuthMetadata.discover(issuer, options)
    assert result["issuer"] == issuer

    assert_receive {:request,
                    "https://auth.example.test/.well-known/oauth-authorization-server/tenant"}

    assert_receive {:request, "https://auth.example.test/.well-known/openid-configuration/tenant"}
    assert_receive {:request, "https://auth.example.test/tenant/.well-known/openid-configuration"}
    refute_received {:request, _}
  end

  test "issuer mismatch is terminal and response bodies do not escape errors" do
    owner = self()

    options =
      options(fn _, _, _ ->
        send(owner, :requested)
        response(metadata("https://other.example.test"))
      end)

    assert {:error, :invalid_oauth_metadata} =
             OAuthMetadata.discover("https://auth.example.test", options)

    assert_receive :requested
    refute_received :requested
  end

  test "private destinations are rejected before HTTP and invalid issuers never resolve" do
    owner = self()

    options = [
      dns_resolver: fn _, _ -> {:ok, [{127, 0, 0, 1}]} end,
      http_client: fn _, _, _ ->
        send(owner, :http)
        response(%{})
      end
    ]

    assert {:error, :oauth_metadata_unavailable} =
             OAuthMetadata.discover("https://auth.example.test", options)

    assert {:error, :invalid_oauth_issuer} =
             OAuthMetadata.discover("https://auth.example.test?secret=x", options)

    refute_received :http
  end

  test "issuer response capability is retained and must be boolean" do
    issuer = "https://auth.example.test"

    for value <- [true, false] do
      opts =
        options(fn _, _, _ ->
          response(
            Map.put(metadata(issuer), "authorization_response_iss_parameter_supported", value)
          )
        end)

      assert {:ok, result} = OAuthMetadata.discover(issuer, opts)
      assert result["authorization_response_iss_parameter_supported"] == value
    end

    opts =
      options(fn _, _, _ ->
        response(
          Map.put(metadata(issuer), "authorization_response_iss_parameter_supported", "true")
        )
      end)

    assert {:error, :invalid_oauth_metadata} = OAuthMetadata.discover(issuer, opts)
  end

  test "explicit non-browser grants can discover a token-only authorization server" do
    issuer = "https://auth.example.test"

    machine =
      metadata(issuer)
      |> Map.delete("authorization_endpoint")
      |> Map.put("grant_types_supported", ["client_credentials"])

    assert {:ok, result} =
             OAuthMetadata.discover(issuer, options(fn _, _, _ -> response(machine) end))

    assert result["token_endpoint"] == issuer <> "/token"
    refute Map.has_key?(result, "authorization_endpoint")

    for invalid <- [
          Map.delete(machine, "grant_types_supported"),
          Map.put(machine, "grant_types_supported", ["authorization_code"]),
          Map.put(machine, "grant_types_supported", ["implicit"]),
          Map.delete(machine, "token_endpoint")
        ] do
      assert {:error, :invalid_oauth_metadata} =
               OAuthMetadata.discover(issuer, options(fn _, _, _ -> response(invalid) end))
    end
  end

  test "retained capability metadata is typed and bounded before it reaches discovery results" do
    issuer = "https://auth.example.test"

    invalid_fields = [
      {"scopes_supported", "tools:read"},
      {"scopes_supported", ["tools:read", nil]},
      {"scopes_supported", ["two scopes"]},
      {"scopes_supported", List.duplicate("read", 65)},
      {"grant_types_supported", ["authorization_code", 7]},
      {"response_types_supported", ["code", nil]},
      {"code_challenge_methods_supported", "S256"},
      {"token_endpoint_auth_methods_supported", ["none", %{}]},
      {"client_id_metadata_document_supported", "true"},
      {"response_types_supported", [String.duplicate("x", 257)]}
    ]

    for {field, invalid} <- invalid_fields do
      body = Map.put(metadata(issuer), field, invalid)

      assert {:error, :invalid_oauth_metadata} =
               OAuthMetadata.discover(issuer, options(fn _, _, _ -> response(body) end))
    end
  end

  defp options(client),
    do: [dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end, http_client: client]

  defp response(body), do: {:ok, %{status: 200, headers: [], body: JSON.encode!(body)}}

  defp metadata(issuer),
    do: %{
      "issuer" => issuer,
      "authorization_endpoint" => "https://auth.example.test/authorize",
      "token_endpoint" => "https://auth.example.test/token"
    }
end
