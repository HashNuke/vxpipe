defmodule Vxpipe.MCP.OAuthAuthorizationTest do
  use ExUnit.Case, async: true
  alias Vxpipe.MCP.OAuthAuthorization

  @metadata %{
    "issuer" => "https://auth.example.test",
    "authorization_endpoint" => "https://auth.example.test/authorize",
    "token_endpoint" => "https://auth.example.test/token",
    "code_challenge_methods_supported" => ["S256"],
    "response_types_supported" => ["code"],
    "authorization_response_iss_parameter_supported" => true
  }

  @context %{
    origin: "https://console.example.test",
    resource: "https://mcp.example.test/mcp",
    scopes: ["tools:read"]
  }

  test "shared callback requires explicit issuer-response support" do
    for supported <- [nil, false, "true"] do
      metadata = Map.put(@metadata, "authorization_response_iss_parameter_supported", supported)

      assert {:error, :unsupported_oauth_capabilities} =
               OAuthAuthorization.build(metadata, "client", @context)
    end
  end

  test "Own-client literal parameters and audience cannot replace managed authorization fields" do
    context =
      Map.merge(@context, %{
        parameters: [%{"name" => "prompt", "value" => "consent"}],
        audience: "provider-api"
      })

    assert {:ok, request} = OAuthAuthorization.build(@metadata, "registered", context)
    query = request.authorization_url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert query["prompt"] == "consent"
    assert query["audience"] == "provider-api"
    assert query["resource"] == @context.resource
    assert query["client_id"] == "registered"
    assert query["state"] == request.state

    for name <- ~w(state client_id code_challenge redirect_uri resource audience) do
      context = Map.put(@context, :parameters, [%{"name" => name, "value" => "override"}])

      assert {:error, :invalid_oauth_authorization} =
               OAuthAuthorization.build(@metadata, "registered", context)
    end
  end

  test "authorization is bound to installation callback, resource, state and S256 verifier" do
    assert {:ok, request} = OAuthAuthorization.build(@metadata, "client", @context)
    uri = URI.parse(request.authorization_url)
    query = URI.decode_query(uri.query)
    assert query["redirect_uri"] == "https://console.example.test/oauth/mcp/callback"
    assert query["resource"] == @context.resource
    assert query["scope"] == "tools:read"
    assert query["response_type"] == "code"
    assert query["state"] == request.state
    assert query["code_challenge_method"] == "S256"

    assert query["code_challenge"] ==
             ExMCP.Authorization.PKCE.generate_code_challenge(request.code_verifier)

    assert request.issuer == @metadata["issuer"]
    refute inspect(request) =~ request.code_verifier
    refute inspect(request) =~ request.state
    assert {:ok, next} = OAuthAuthorization.build(@metadata, "client", @context)
    refute next.state == request.state
  end

  test "unsupported PKCE and endpoint query overrides fail before any authorization URL is returned" do
    assert {:error, :unsupported_oauth_capabilities} =
             OAuthAuthorization.build(
               Map.delete(@metadata, "code_challenge_methods_supported"),
               "client",
               @context
             )

    metadata =
      Map.put(
        @metadata,
        "authorization_endpoint",
        "https://auth.example.test/authorize?state=chosen"
      )

    assert {:error, :invalid_oauth_authorization} =
             OAuthAuthorization.build(metadata, "client", @context)

    assert {:error, :invalid_oauth_authorization} =
             OAuthAuthorization.build(@metadata, "", @context)
  end

  test "installation URL, resource and scope are validated, never guessed" do
    for context <- [
          %{@context | origin: "http://console.example.test"},
          %{@context | resource: "https://user:pass@mcp.example.test/mcp"},
          %{@context | scopes: ["read write"]}
        ] do
      assert {:error, :invalid_oauth_authorization} =
               OAuthAuthorization.build(@metadata, "client", context)
    end
  end

  test "authorization endpoint query cannot hide request-object overrides or duplicate supplied parameters" do
    for query <- [
          "request_uri=https%3A%2F%2Fexample.test%2Frequest",
          "response_mode=form_post",
          "prompt=one&prompt=two"
        ] do
      metadata =
        Map.put(
          @metadata,
          "authorization_endpoint",
          "https://auth.example.test/authorize?" <> query
        )

      assert {:error, :invalid_oauth_authorization} =
               OAuthAuthorization.build(metadata, "client", @context)
    end

    metadata =
      Map.put(
        @metadata,
        "authorization_endpoint",
        "https://auth.example.test/authorize?prompt=one"
      )

    context = Map.put(@context, :parameters, [%{"name" => "prompt", "value" => "two"}])

    assert {:error, :invalid_oauth_authorization} =
             OAuthAuthorization.build(metadata, "client", context)
  end
end
