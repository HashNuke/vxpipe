defmodule Vxpipe.Identity.OAuth.ProfileTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Identity.OAuth.Profile

  @resource "https://vxpipe.example/mcp"
  @client "11111111-1111-4111-8111-111111111111"
  @redirect "http://127.0.0.1:41000/callback"
  @verifier String.duplicate("a", 43)
  @challenge :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false)

  test "public registration fixes the client security profile without accepting authority" do
    assert {:ok, client} =
             Profile.registration(%{
               "client_name" => "Local MCP client",
               "redirect_uris" => [@redirect, "https://client.example/callback"]
             })

    assert client["token_endpoint_auth_method"] == "none"
    assert client["grant_types"] == ["authorization_code", "refresh_token"]
    assert client["response_types"] == ["code"]
    assert client["scope"] == "mcp"

    for extra <- [
          %{"grant_types" => ["client_credentials"]},
          %{"token_endpoint_auth_method" => "client_secret_post"},
          %{"scope" => "platform"},
          %{"jwks_uri" => "http://127.0.0.1/private"},
          %{"client_id" => @client}
        ] do
      assert {:error, :invalid_client_metadata} =
               Profile.registration(
                 Map.merge(%{"client_name" => "Client", "redirect_uris" => [@redirect]}, extra)
               )
    end
  end

  test "redirects allow explicit native loopback callbacks but reject unsafe registrations" do
    for uri <- [
          @redirect,
          "http://[::1]:41000/callback",
          "https://client.example/callback?flow=mcp"
        ] do
      assert {:ok, _} =
               Profile.registration(%{"client_name" => "Client", "redirect_uris" => [uri]})
    end

    for uri <- [
          "http://client.example/callback",
          "http://localhost:41000/callback",
          "https://client.example/*",
          "https://user@client.example/callback",
          "https://client.example/callback#fragment",
          "https://client.example/callback\r\n",
          "//client.example/callback",
          "javascript:alert(1)",
          "https://client.example/\\callback"
        ] do
      assert {:error, :invalid_client_metadata} =
               Profile.registration(%{"client_name" => "Client", "redirect_uris" => [uri]})
    end

    assert {:error, :invalid_client_metadata} =
             Profile.registration(%{
               "client_name" => "Client",
               "redirect_uris" => List.duplicate(@redirect, 6)
             })
  end

  test "authorization binds the exact resource and requires S256 before Boruta processing" do
    assert {:ok, accepted} = Profile.authorization(authorization(), @resource)
    assert accepted["resource"] == @resource

    for change <- [
          %{"resource" => "https://other.example/mcp"},
          %{"resource" => @resource <> "/"},
          %{"resource" => [@resource, "https://other.example/mcp"]},
          %{"code_challenge_method" => "plain"},
          %{"code_challenge" => "short"},
          %{"scope" => "mcp users.write"},
          %{"request_uri" => "https://other.example/request"},
          %{"response_type" => "token"}
        ] do
      assert {:error, _safe_code} =
               Profile.authorization(Map.merge(authorization(), change), @resource)
    end

    assert {:error, :invalid_target} =
             Profile.authorization(Map.delete(authorization(), "resource"), @resource)

    assert {:error, :invalid_request} =
             Profile.authorization(
               Map.delete(authorization(), "code_challenge_method"),
               @resource
             )
  end

  test "code exchange requires resource, verifier and exact redirect; refresh retains its resource" do
    exchange = %{
      "grant_type" => "authorization_code",
      "client_id" => @client,
      "redirect_uri" => @redirect,
      "resource" => @resource,
      "code" => String.duplicate("c", 43),
      "code_verifier" => @verifier
    }

    assert {:ok, ^exchange} = Profile.token(exchange, @resource)
    assert {:error, :invalid_target} = Profile.token(Map.delete(exchange, "resource"), @resource)

    assert {:error, :invalid_request} =
             Profile.token(Map.put(exchange, "code_verifier", "bad"), @resource)

    assert {:error, :invalid_request} =
             Profile.token(Map.put(exchange, "client_secret", "secret"), @resource)

    refresh = %{
      "grant_type" => "refresh_token",
      "client_id" => @client,
      "refresh_token" => String.duplicate("r", 43)
    }

    assert {:ok, ^refresh} = Profile.token(refresh, @resource)

    assert {:error, :invalid_target} =
             Profile.token(Map.put(refresh, "resource", "https://other.example/mcp"), @resource)

    assert {:error, :unsupported_grant_type} =
             Profile.token(%{"grant_type" => "password"}, @resource)
  end

  test "revocation accepts only public-client token credentials and bounded hints" do
    params = %{"client_id" => @client, "token" => String.duplicate("t", 43)}
    assert {:ok, ^params} = Profile.revocation(params)

    assert {:error, :invalid_request} =
             Profile.revocation(Map.put(params, "token", String.duplicate("s", 257)))

    assert {:error, :invalid_request} =
             Profile.revocation(Map.put(params, "token_type_hint", "password"))
  end

  defp authorization do
    %{
      "response_type" => "code",
      "client_id" => @client,
      "redirect_uri" => @redirect,
      "resource" => @resource,
      "scope" => "mcp",
      "state" => "opaque-client-state",
      "code_challenge_method" => "S256",
      "code_challenge" => @challenge
    }
  end
end
