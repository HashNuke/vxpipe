defmodule Vxpipe.MCP.OAuthPreparationTest do
  use ExUnit.Case, async: true
  alias Vxpipe.MCP.OAuthPreparation
  @endpoint "https://mcp.example.test/mcp"
  @issuer "https://auth.example.test"
  @origin "https://console.example.test"

  test "Connect rediscovers metadata and prepares private bound authorization" do
    assert {:ok, prepared} = OAuthPreparation.prepare(input(), @origin, options())
    assert prepared.authorization.resource == @endpoint
    assert prepared.authorization.issuer == @issuer
    assert prepared.authorization.client_id == @origin <> "/oauth/client-metadata.json"
    assert prepared.authorization.scopes == ["tools:read"]
    assert prepared.token_endpoint == @issuer <> "/token"
    assert prepared.draft_revision == "revision"
    assert prepared.issuer_response_required
    refute inspect(prepared) =~ "code_verifier"
    assert_receive :resource_discovery
    assert_receive :oauth_discovery
    refute_received :registration
  end

  test "unadvertised issuer and browser-supplied endpoints cannot direct OAuth" do
    assert {:error, :invalid_oauth_issuer} =
             OAuthPreparation.prepare(
               Map.put(input(), "issuer", "https://other.test"),
               @origin,
               options()
             )

    refute_received :oauth_discovery

    assert {:error, :invalid_oauth_preparation} =
             OAuthPreparation.prepare(
               Map.put(input(), "token_endpoint", "https://other.test/token"),
               @origin,
               options()
             )
  end

  test "unsupported PKCE rejects before DCR side effects" do
    assert {:error, :unsupported_oauth_capabilities} =
             OAuthPreparation.prepare(
               %{input() | "auth_method" => "dcr"},
               @origin,
               options(["plain"])
             )

    refute_received :registration
  end

  test "protected token query is rejected before DCR side effects" do
    opts =
      options(["S256"], true, nil, %{"token_endpoint" => @issuer <> "/token?grant_type=password"})

    assert {:error, :invalid_oauth_parameters} =
             OAuthPreparation.prepare(%{input() | "auth_method" => "dcr"}, @origin, opts)

    refute_received :registration
  end

  test "managed registration uses challenge scopes and only supported grants" do
    opts =
      options(["S256"], true, "events:read", %{"grant_types_supported" => ["authorization_code"]})

    assert {:ok, prepared} =
             OAuthPreparation.prepare(%{input() | "auth_method" => "dcr"}, @origin, opts)

    assert_receive {:registration_body, body}
    assert body["scope"] == "events:read"
    assert body["grant_types"] == ["authorization_code"]
    assert prepared.authorization.scopes == ["events:read"]
  end

  test "DCR registration feeds its returned client into the authorization request" do
    assert {:ok, prepared} =
             OAuthPreparation.prepare(%{input() | "auth_method" => "dcr"}, @origin, options())

    assert prepared.authorization.client_id == "registered-client"
    assert prepared.client.client_id == "registered-client"
    assert_receive :registration
  end

  test "challenge scopes take precedence even when absent from resource scopes_supported" do
    for method <- ["cimd", "dcr"] do
      assert {:ok, prepared} =
               OAuthPreparation.prepare(
                 %{input() | "auth_method" => method},
                 @origin,
                 options(["S256"], true, "events:read")
               )

      assert prepared.authorization.scopes == ["events:read"]
      query = prepared.authorization.authorization_url |> URI.parse() |> Map.fetch!(:query)
      assert URI.decode_query(query)["scope"] == "events:read"
    end
  end

  test "missing issuer-response protection rejects before DCR side effects" do
    assert {:error, :unsupported_oauth_capabilities} =
             OAuthPreparation.prepare(
               %{input() | "auth_method" => "dcr"},
               @origin,
               options(["S256"], false)
             )

    refute_received :registration
  end

  test "fresh discovery reuses a matching saved DCR registration without registering again" do
    for method <- ["none", "client_secret_basic"] do
      saved = registration(method)
      opts = Keyword.put(options(), :registration, saved)

      assert {:ok, prepared} =
               OAuthPreparation.prepare(%{input() | "auth_method" => "dcr"}, @origin, opts)

      assert prepared.client.client_id == "saved-client"
      assert prepared.authorization.client_id == "saved-client"
      assert_receive :resource_discovery
      assert_receive :oauth_discovery
      refute_received :registration
      refute inspect(prepared) =~ "saved-secret"
    end
  end

  test "mismatched, unsupported and expired registrations require fresh explicit registration" do
    for change <- [
          %{"issuer" => "https://other.test"},
          %{"resource" => "https://other.test/mcp"},
          %{"redirect_uri" => "https://other.test/callback"},
          %{"registration_method" => "cimd"},
          %{"auth_method" => "private_key_jwt"},
          %{"client_secret_expires_at" => 1},
          %{"client_secret_expires_at" => nil},
          %{"client_id" => ""}
        ] do
      opts =
        Keyword.put(
          options(),
          :registration,
          Map.merge(registration("client_secret_basic"), change)
        )

      assert {:ok, prepared} =
               OAuthPreparation.prepare(%{input() | "auth_method" => "dcr"}, @origin, opts)

      assert prepared.client.client_id == "registered-client"
      assert_receive :registration
    end
  end

  test "an explicit initial access token requests fresh DCR even with a reusable registration" do
    opts = Keyword.put(options(), :registration, registration("none"))

    input =
      Map.merge(input(), %{
        "auth_method" => "dcr",
        "initial_access_token" => "new-registration-token"
      })

    assert {:ok, prepared} = OAuthPreparation.prepare(input, @origin, opts)
    assert prepared.client.client_id == "registered-client"
    assert_receive :registration
  end

  test "DCR scope coverage is checked again after fresh challenge discovery" do
    for scopes <- [nil, [], ["tools:read"]] do
      saved = Map.put(registration("none"), "scopes", scopes)
      opts = Keyword.put(options(["S256"], true, "tools:write"), :registration, saved)

      assert {:ok, prepared} =
               OAuthPreparation.prepare(%{input() | "auth_method" => "dcr"}, @origin, opts)

      assert prepared.client.client_id == "registered-client"
      assert_receive :registration
      assert_receive {:registration_body, body}
      assert body["scope"] == "tools:write"
    end

    saved = Map.put(registration("none"), "scopes", ["tools:read", "tools:write"])
    opts = Keyword.put(options(), :registration, saved)

    assert {:ok, prepared} =
             OAuthPreparation.prepare(%{input() | "auth_method" => "dcr"}, @origin, opts)

    assert prepared.client.client_id == "saved-client"
    refute_received :registration
  end

  defp registration(method) do
    %{
      "registration_method" => "dcr",
      "issuer" => @issuer,
      "resource" => @endpoint,
      "redirect_uri" => @origin <> "/oauth/mcp/callback",
      "client_id" => "saved-client",
      "auth_method" => method,
      "scopes" => ["tools:read"],
      "client_secret" => if(method == "none", do: nil, else: "saved-secret"),
      "client_secret_expires_at" => if(method == "none", do: nil, else: 0)
    }
  end

  defp input, do: %{"endpoint" => @endpoint, "revision" => "revision", "auth_method" => "cimd"}

  defp options(
         challenges \\ ["S256"],
         issuer_response \\ true,
         scope \\ nil,
         metadata_changes \\ %{}
       ) do
    owner = self()

    [
      dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end,
      http_client: fn uri, _, _ ->
        cond do
          uri.path == "/mcp" ->
            headers = if scope, do: [{"www-authenticate", "Bearer scope=\"#{scope}\""}], else: []
            {:ok, %{status: 401, headers: headers, body: "{}"}}

          uri.host == "mcp.example.test" ->
            send(owner, :resource_discovery)

            response(200, %{
              "resource" => @endpoint,
              "authorization_servers" => [@issuer],
              "scopes_supported" => ["tools:read"]
            })

          true ->
            send(owner, :oauth_discovery)

            metadata = %{
              "issuer" => @issuer,
              "authorization_endpoint" => @issuer <> "/authorize",
              "token_endpoint" => @issuer <> "/token",
              "registration_endpoint" => @issuer <> "/register",
              "client_id_metadata_document_supported" => true,
              "code_challenge_methods_supported" => challenges,
              "response_types_supported" => ["code"],
              "token_endpoint_auth_methods_supported" => ["none", "client_secret_basic"],
              "authorization_response_iss_parameter_supported" => issuer_response
            }

            response(200, Map.merge(metadata, metadata_changes))
        end
      end,
      request_fun: fn _, {_, _, _, body}, _, _ ->
        send(owner, :registration)
        send(owner, {:registration_body, JSON.decode!(body)})

        {:ok,
         {{~c"HTTP/1.1", 201, ~c"Created"}, [],
          JSON.encode!(%{
            "client_id" => "registered-client",
            "token_endpoint_auth_method" => "none",
            "redirect_uris" => [@origin <> "/oauth/mcp/callback"]
          })}}
      end
    ]
  end

  defp response(status, body), do: {:ok, %{status: status, headers: [], body: JSON.encode!(body)}}
end
