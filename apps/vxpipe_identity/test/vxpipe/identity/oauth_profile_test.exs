defmodule Vxpipe.Identity.OAuth.ProfileTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Identity.OAuth.Profile

  @resource "https://vxpipe.example/mcp"
  @client "11111111-1111-4111-8111-111111111111"
  @redirect "http://127.0.0.1:41000/callback"
  @verifier String.duplicate("a", 43)
  @challenge :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false)

  test "DCR and CIMD retain optional HTTPS branding without extending the security profile" do
    branding = %{
      "client_name" => "Research client",
      "redirect_uris" => [@redirect],
      "client_uri" => "https://client.example/about",
      "logo_uri" => "https://client.example/logo.png"
    }

    assert {:ok, registered} = Profile.registration(branding)
    assert registered["logo_uri"] == branding["logo_uri"]
    assert registered["client_uri"] == branding["client_uri"]
    id = "https://client.example/oauth/client.json"
    assert {:ok, ^registered} = Profile.client_metadata(Map.put(branding, "client_id", id), id)
  end

  test "optional branding rejects unsafe or unbounded URLs at registration" do
    for field <- ["client_uri", "logo_uri"],
        value <- [
          "http://127.0.0.1/logo.png",
          "https://user:password@client.example/logo.png",
          "javascript:alert(1)",
          "data:image/png;base64,AA==",
          "https://client.example/\\logo.png",
          "https://client.example/logo.png\n",
          "https://client.example/" <> String.duplicate("a", 2_048),
          ["https://client.example/logo.png"]
        ] do
      assert {:error, :invalid_client_metadata} =
               Profile.registration(%{
                 "client_name" => "Client",
                 "redirect_uris" => [@redirect],
                 field => value
               })
    end
  end

  test "Codex native registration metadata is accepted" do
    assert {:ok, metadata} =
             Profile.registration(%{
               "client_name" => "Codex",
               "application_type" => "native",
               "redirect_uris" => [@redirect]
             })

    assert metadata["application_type"] == "native"
  end

  test "CIMD identifiers remain exact HTTPS document URLs throughout OAuth" do
    id = "https://client.example:443/oauth/client.json"

    assert {:ok, params} =
             Profile.authorization(Map.put(authorization(), "client_id", id), @resource)

    assert params["client_id"] == id

    assert {:ok, _} =
             Profile.token(
               %{"grant_type" => "refresh_token", "client_id" => id, "refresh_token" => "token"},
               @resource
             )

    assert {:ok, _} = Profile.revocation(%{"client_id" => id, "token" => "token"})

    for invalid <- [
          "http://client.example/client.json",
          "https://client.example/",
          "https://user@client.example/client.json",
          "https://client.example/a/../client.json",
          id <> "#fragment"
        ] do
      assert {:error, :invalid_request} =
               Profile.authorization(Map.put(authorization(), "client_id", invalid), @resource)
    end
  end

  test "loopback redirect matching permits only a different port" do
    assert Profile.redirect_matches?(@redirect, ["http://127.0.0.1/callback"])
    assert Profile.redirect_matches?("http://[::1]:45321/callback", ["http://[::1]/callback"])

    for rejected <- [
          "http://localhost:41000/callback",
          "http://127.0.0.1:41000/other",
          "http://127.0.0.1:41000/callback?extra=1",
          "https://127.0.0.1:41000/callback"
        ] do
      refute Profile.redirect_matches?(rejected, ["http://127.0.0.1/callback"])
    end

    refute Profile.redirect_matches?("https://client.example:45321/callback", [
             "https://client.example/callback"
           ])
  end

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
