defmodule Vxpipe.MCP.OwnOAuthConfigurationTest do
  use ExUnit.Case, async: true
  alias Vxpipe.MCP.{OAuthClientAssertion, OwnOAuthConfiguration}
  @endpoint "https://mcp.example.test/mcp"
  @issuer "https://auth.example.test"
  @origin "https://console.example.test"
  @resource %{
    "resource" => @endpoint,
    "authorization_servers" => [@issuer],
    "scopes_supported" => ["tools:read"]
  }
  @metadata %{
    "issuer" => @issuer,
    "authorization_endpoint" => @issuer <> "/authorize",
    "token_endpoint" => @issuer <> "/token",
    "grant_types_supported" => ["authorization_code", "refresh_token", "client_credentials"],
    "token_endpoint_auth_methods_supported" => [
      "none",
      "client_secret_basic",
      "client_secret_post",
      "private_key_jwt"
    ],
    "token_endpoint_auth_signing_alg_values_supported" => ["RS256", "ES256"],
    "response_types_supported" => ["code"],
    "code_challenge_methods_supported" => ["S256"],
    "authorization_response_iss_parameter_supported" => true
  }

  test "registered confidential configuration uses discovery defaults and separates destinations" do
    values =
      Map.merge(credentials(), %{
        "authorization_endpoint" => @issuer <> "/custom-authorize",
        "token_endpoint" => @issuer <> "/custom-token",
        "revocation_endpoint" => @issuer <> "/revoke",
        "scopes" => ["calendar:read"],
        "audience" => "calendar-api",
        "authorization_parameters" => [%{"name" => "prompt", "value" => "consent"}],
        "token_parameters" => [%{"name" => "organization", "value" => "private-org"}],
        "headers" => [%{"name" => "X-Workspace", "value" => "private-workspace"}]
      })

    assert {:ok, config} = build(values)
    assert config.grant_type == "authorization_code"
    assert config.metadata["authorization_endpoint"] == @issuer <> "/custom-authorize"
    assert config.token_request.token_endpoint == @issuer <> "/custom-token"
    assert config.token_request.auth_method == :client_secret_basic
    assert config.token_request.client_secret == "private-secret"
    assert config.token_request.resource == @endpoint
    assert config.token_request.parameters == values["token_parameters"]

    assert config.authorization_context == %{
             origin: @origin,
             resource: @endpoint,
             scopes: ["calendar:read"],
             audience: "calendar-api",
             parameters: values["authorization_parameters"]
           }

    refute Map.has_key?(config.token_request, :headers)
    assert config.secrets["headers"] == values["headers"]
    assert config.secrets["registration_method"] == "own_client"
    assert config.secrets["grant_type"] == "authorization_code"
    assert config.secrets["redirect_uri"] == @origin <> "/oauth/mcp/callback"
    assert config.secrets["revocation_endpoint"] == @issuer <> "/revoke"
    refute inspect(config) =~ "private-secret"
    refute inspect(config) =~ "private-org"
    assert JSON.decode!(JSON.encode!(config.secrets)) == config.secrets

    assert {:ok, defaults} = build(credentials())
    assert defaults.token_request.token_endpoint == @metadata["token_endpoint"]
    assert defaults.authorization_context.scopes == ["tools:read"]
  end

  test "public client has no secret and machine grants have no browser configuration" do
    public = credentials() |> Map.put("client_auth_method", "none") |> Map.delete("client_secret")
    assert {:ok, config} = build(public)
    assert config.token_request.auth_method == :none
    refute Map.has_key?(config.token_request, :client_secret)

    assert {:error, :invalid_own_oauth_configuration} =
             build(Map.put(public, "client_secret", "stale"))

    assert {:error, :invalid_own_oauth_configuration} =
             build(Map.put(public, "grant_type", "client_credentials"))

    machine = Map.put(credentials(), "grant_type", "client_credentials")
    assert {:ok, config} = build(machine, @metadata, nil)
    assert is_nil(config.authorization_context)
    assert config.token_request.scope == "tools:read"
    refute Map.has_key?(config.secrets, "redirect_uri")

    for field <- ["authorization_endpoint", "authorization_parameters"] do
      value = if field == "authorization_parameters", do: [], else: @issuer <> "/authorize"
      assert {:error, :invalid_own_oauth_configuration} = build(Map.put(machine, field, value))
    end
  end

  test "key authentication retains encrypted-store input without sending key material as token fields" do
    rsa = :public_key.generate_key({:rsa, 2048, 65_537})
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, rsa)])

    values =
      credentials()
      |> Map.delete("client_secret")
      |> Map.merge(%{
        "client_auth_method" => "private_key_jwt",
        "private_key" => pem,
        "algorithm" => "RS256",
        "key_id" => "registered-key"
      })

    assert {:ok, config} = build(values)
    assert %OAuthClientAssertion{} = config.token_request.client_assertion
    assert config.secrets["private_key"] == pem
    assert config.secrets["signing_algorithms"] == ["RS256", "ES256"]
    refute inspect(config) =~ pem
    refute Map.has_key?(config.token_request, :private_key)
    refute Map.has_key?(config.secrets, "client_assertion")
    assert JSON.decode!(JSON.encode!(config.secrets)) == config.secrets

    assert {:error, :invalid_own_oauth_configuration} =
             build(
               values,
               Map.delete(@metadata, "token_endpoint_auth_signing_alg_values_supported")
             )

    assert {:error, :invalid_own_oauth_configuration} =
             build(Map.put(values, "client_secret", "mixed"))
  end

  test "rejects unsupported grants/methods and untrusted metadata or endpoint replacements" do
    for metadata <- [
          Map.put(@metadata, "issuer", "https://other.example.test"),
          Map.put(@metadata, "token_endpoint_auth_methods_supported", ["none"]),
          Map.put(@metadata, "grant_types_supported", ["client_credentials"]),
          Map.put(@metadata, "code_challenge_methods_supported", ["plain"]),
          Map.put(@metadata, "authorization_response_iss_parameter_supported", false)
        ] do
      assert {:error, :invalid_own_oauth_configuration} = build(credentials(), metadata)
    end

    for {field, value} <- [
          {"grant_type", "password"},
          {"client_auth_method", "client_secret_jwt"},
          {"client_id", ""},
          {"token_endpoint", "https://other.example.test/token"},
          {"authorization_endpoint", "http://auth.example.test/authorize"},
          {"revocation_endpoint", "https://user:secret@auth.example.test/revoke"},
          {"resource", "https://other.example.test/mcp"},
          {"scopes", ["invalid scope"]},
          {"state", "chosen"},
          {"redirect_uri", "https://other.example.test/callback"},
          {"private_key", "inactive"},
          {"algorithm", "inactive"},
          {"token_endpoint_auth_methods_supported", ["client_secret_basic"]},
          {"authorization_parameters", [%{"name" => "request_uri", "value" => "override"}]},
          {"token_parameters", [%{"name" => "grant_type", "value" => "override"}]},
          {"headers", [%{"name" => "Authorization", "value" => "override"}]}
        ] do
      assert {:error, :invalid_own_oauth_configuration} =
               build(Map.put(credentials(), field, value))
    end
  end

  test "configuration rejects query conflicts and requires a choice for multiple issuers" do
    for {endpoint, pairs} <- [
          {"authorization_endpoint", "authorization_parameters"},
          {"token_endpoint", "token_parameters"}
        ] do
      values =
        Map.merge(credentials(), %{
          endpoint => @issuer <> "/operation?organization=default",
          pairs => [%{"name" => "organization", "value" => "different"}]
        })

      assert {:error, :invalid_own_oauth_configuration} = build(values)
    end

    input = %{
      "endpoint" => @endpoint,
      "revision" => "draft",
      "auth_method" => "own_client",
      "credentials" => credentials()
    }

    resource =
      Map.put(@resource, "authorization_servers", [@issuer, "https://other.example.test"])

    assert {:error, :invalid_own_oauth_configuration} =
             OwnOAuthConfiguration.new(input, @metadata, resource, @origin)

    assert {:ok, _} =
             OwnOAuthConfiguration.new(
               Map.put(input, "issuer", @issuer),
               @metadata,
               resource,
               @origin
             )
  end

  defp credentials,
    do: %{
      "grant_type" => "authorization_code",
      "client_id" => "registered",
      "client_auth_method" => "client_secret_basic",
      "client_secret" => "private-secret"
    }

  defp build(values, metadata \\ @metadata, origin \\ @origin),
    do:
      OwnOAuthConfiguration.new(
        %{
          "endpoint" => @endpoint,
          "revision" => "draft",
          "auth_method" => "own_client",
          "credentials" => values
        },
        metadata,
        @resource,
        origin
      )
end
