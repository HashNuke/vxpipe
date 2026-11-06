defmodule Vxpipe.MCP.OAuthRegistrationTest do
  use ExUnit.Case, async: true
  alias Vxpipe.MCP.OAuthRegistration
  @origin "https://console.example.test"
  @metadata %{
    "issuer" => "https://auth.example.test",
    "authorization_endpoint" => "https://auth.example.test/authorize",
    "token_endpoint" => "https://auth.example.test/token",
    "registration_endpoint" => "https://auth.example.test/register",
    "token_endpoint_auth_methods_supported" => ["none"],
    "client_id_metadata_document_supported" => true
  }

  test "CIMD uses installation identity without registration HTTP" do
    assert {:ok, client} = OAuthRegistration.register(:cimd, @metadata, @origin, nil)
    assert client.client_id == @origin <> "/oauth/client-metadata.json"
    assert client.auth_method == :none

    assert {:error, :oauth_registration_unavailable} =
             OAuthRegistration.register(
               :cimd,
               Map.delete(@metadata, "client_id_metadata_document_supported"),
               @origin,
               nil
             )
  end

  test "DCR sends managed metadata and optional initial token only to registration" do
    owner = self()

    opts =
      options(fn :post, {url, headers, _, body}, http, _ ->
        send(owner, {:registration, to_string(url), headers, JSON.decode!(body), http})

        response(%{
          "client_id" => "registered",
          "token_endpoint_auth_method" => "none",
          "redirect_uris" => [@origin <> "/oauth/mcp/callback"]
        })
      end)

    assert {:ok, client} =
             OAuthRegistration.register(:dcr, @metadata, @origin, "initial-secret", opts)

    assert client.client_id == "registered"
    assert client.auth_method == :none
    refute inspect(client) =~ "registered"
    assert_receive {:registration, "https://93.184.216.34/register", headers, body, http}
    assert {~c"authorization", ~c"Bearer initial-secret"} in headers
    assert body["redirect_uris"] == [@origin <> "/oauth/mcp/callback"]
    assert body["token_endpoint_auth_method"] == "none"
    refute Map.has_key?(body, "initial_access_token")
    assert http[:autoredirect] == false
  end

  test "CIMD requires support for the installation's public client authentication" do
    for metadata <- [
          Map.put(@metadata, "token_endpoint_auth_methods_supported", ["client_secret_basic"]),
          Map.delete(@metadata, "token_endpoint_auth_methods_supported")
        ] do
      assert {:error, :oauth_registration_unavailable} =
               OAuthRegistration.register(
                 :cimd,
                 metadata,
                 @origin,
                 nil,
                 options(fn _, _, _, _ ->
                   flunk("CIMD cannot register to repair incompatible auth")
                 end)
               )
    end
  end

  test "DCR requests supported grants and selected scopes, and omits empty scope" do
    owner = self()

    for {supported, expected} <- [
          {["authorization_code"], ["authorization_code"]},
          {["authorization_code", "refresh_token"], ["authorization_code", "refresh_token"]}
        ],
        scopes <- [[], ["tools:read"]] do
      metadata = Map.put(@metadata, "grant_types_supported", supported)

      opts =
        options(fn _, {_, _, _, body}, _, _ ->
          body = JSON.decode!(body)
          send(owner, {:registered, body})
          response(Map.put(body, "client_id", "registered"))
        end)
        |> Keyword.put(:scopes, scopes)

      assert {:ok, _} = OAuthRegistration.register(:dcr, metadata, @origin, nil, opts)
      assert_receive {:registered, body}
      assert body["grant_types"] == expected
      assert body["response_types"] == ["code"]

      if scopes == [],
        do: refute(Map.has_key?(body, "scope")),
        else: assert(body["scope"] == "tools:read")
    end
  end

  test "DCR rejects explicit registration metadata incompatible with the selected authorization" do
    for change <- [
          %{"grant_types" => ["client_credentials"]},
          %{"response_types" => ["token"]},
          %{"scope" => "tools:write"},
          %{"scope" => "tools:read\nadmin"}
        ] do
      opts =
        options(fn _, {_, _, _, body}, _, _ ->
          body
          |> JSON.decode!()
          |> Map.put("client_id", "registered")
          |> Map.merge(change)
          |> response()
        end)
        |> Keyword.put(:scopes, ["tools:read"])

      assert {:error, :invalid_oauth_registration} =
               OAuthRegistration.register(:dcr, @metadata, @origin, nil, opts)
    end
  end

  test "server cannot replace callback or silently change client authentication" do
    for body <- [
          %{
            "client_id" => "client",
            "redirect_uris" => ["https://other.test/callback"],
            "token_endpoint_auth_method" => "none"
          },
          %{
            "client_id" => "client",
            "redirect_uris" => [@origin <> "/oauth/mcp/callback"],
            "token_endpoint_auth_method" => "client_secret_basic"
          }
        ] do
      assert {:error, :invalid_oauth_registration} =
               OAuthRegistration.register(
                 :dcr,
                 @metadata,
                 @origin,
                 nil,
                 options(fn _, _, _, _ -> response(body) end)
               )
    end
  end

  test "registration failures are redacted and never retried" do
    owner = self()

    opts =
      options(fn _, _, _, _ ->
        send(owner, :request)
        {:ok, {{~c"HTTP/1.1", 400, ~c"Bad"}, [], "private-provider-body"}}
      end)

    assert {:error, :oauth_registration_failed} =
             OAuthRegistration.register(:dcr, @metadata, @origin, nil, opts)

    assert_receive :request
    refute_received :request
  end

  test "confidential DCR retains finite and non-expiring secret lifetimes" do
    metadata =
      Map.put(@metadata, "token_endpoint_auth_methods_supported", ["client_secret_basic"])

    for expiry <- [0, System.os_time(:second) + 3600] do
      opts =
        options(fn _, _, _, _ ->
          response(%{
            "client_id" => "registered",
            "client_secret" => "private-secret",
            "client_secret_expires_at" => expiry,
            "token_endpoint_auth_method" => "client_secret_basic",
            "redirect_uris" => [@origin <> "/oauth/mcp/callback"]
          })
        end)

      assert {:ok, client} = OAuthRegistration.register(:dcr, metadata, @origin, nil, opts)
      assert Map.fetch!(client, :client_secret_expires_at) == expiry
      refute inspect(client) =~ "private-secret"
    end
  end

  test "DCR rejects absent, malformed and elapsed issued-secret expiry" do
    metadata =
      Map.put(@metadata, "token_endpoint_auth_methods_supported", ["client_secret_basic"])

    for expiry <- [:absent, nil, -1, "0", 1.5, System.os_time(:second)] do
      body = %{
        "client_id" => "registered",
        "client_secret" => "private-secret",
        "token_endpoint_auth_method" => "client_secret_basic",
        "redirect_uris" => [@origin <> "/oauth/mcp/callback"]
      }

      body =
        if expiry == :absent, do: body, else: Map.put(body, "client_secret_expires_at", expiry)

      assert {:error, :invalid_oauth_registration} =
               OAuthRegistration.register(
                 :dcr,
                 metadata,
                 @origin,
                 nil,
                 options(fn _, _, _, _ -> response(body) end)
               )
    end
  end

  defp options(fun),
    do: [dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end, request_fun: fun]

  defp response(body), do: {:ok, {{~c"HTTP/1.1", 201, ~c"Created"}, [], JSON.encode!(body)}}
end
