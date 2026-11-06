defmodule Vxpipe.MCP.OwnOAuthPreparationTest do
  use ExUnit.Case, async: true
  alias Vxpipe.MCP.{OAuthPreparation, OwnOAuthPreparation}
  @endpoint "https://mcp.example.test/mcp"
  @issuer "https://auth.example.test"
  @origin "https://console.example.test"

  test "Own-client preparation freshly discovers capabilities without registering or exchanging credentials" do
    assert {:ok, prepared} = OAuthPreparation.prepare(input(), @origin, options())
    assert prepared.client.client_id == "registered"
    assert prepared.client.auth_method == :client_secret_basic
    assert prepared.extra_secrets["registration_method"] == "own_client"
    assert prepared.extra_secrets["client_secret"] == "private-secret"

    assert prepared.extra_secrets["headers"] == [
             %{"name" => "X-Workspace", "value" => "workspace"}
           ]

    query =
      prepared.authorization.authorization_url
      |> URI.parse()
      |> Map.fetch!(:query)
      |> URI.decode_query()

    assert query["scope"] == "tools:read"
    assert query["prompt"] == "consent"
    assert query["client_id"] == "registered"
    assert query["resource"] == @endpoint
    assert query["redirect_uri"] == @origin <> "/oauth/mcp/callback"
    assert prepared.authorization.code_verifier
    refute inspect(prepared) =~ "private-secret"
    refute_received :unexpected_write
    assert_received {:discovered, "/.well-known/oauth-authorization-server"}
  end

  test "missing resource metadata permits an explicit issuer but malformed metadata cannot fall back" do
    assert {:error, :oauth_issuer_required} =
             OwnOAuthPreparation.configuration(input(), @origin, options(:missing))

    explicit = Map.put(input(), "issuer", @issuer)
    assert {:ok, config} = OwnOAuthPreparation.configuration(explicit, @origin, options(:missing))
    assert config.metadata["issuer"] == @issuer
    assert_received {:discovered, "/.well-known/oauth-authorization-server"}
    flush_discovery()

    assert {:error, :invalid_resource_metadata} =
             OwnOAuthPreparation.configuration(explicit, @origin, options(:malformed))

    refute_received {:discovered, "/.well-known/oauth-authorization-server"}
    refute_received :unexpected_write
  end

  test "multiple issuers require an advertised choice before authorization metadata is fetched" do
    assert {:error, :oauth_issuer_required} =
             OwnOAuthPreparation.configuration(input(), @origin, options(:multiple))

    refute_received {:discovered, "/.well-known/oauth-authorization-server"}

    assert {:error, :invalid_oauth_issuer} =
             OwnOAuthPreparation.configuration(
               Map.put(input(), "issuer", "https://unadvertised.test"),
               @origin,
               options(:multiple)
             )

    assert {:ok, _} =
             OwnOAuthPreparation.configuration(
               Map.put(input(), "issuer", @issuer),
               @origin,
               options(:multiple)
             )
  end

  test "machine configuration has no browser attempt and rejects the browser handoff path" do
    values =
      input()["credentials"]
      |> Map.put("grant_type", "client_credentials")
      |> Map.delete("authorization_parameters")

    input = Map.put(input(), "credentials", values)
    assert {:ok, config} = OwnOAuthPreparation.configuration(input, nil, options(:machine))
    assert config.grant_type == "client_credentials"
    assert is_nil(config.authorization_context)

    assert {:error, :oauth_browser_grant_required} =
             OAuthPreparation.prepare(input, @origin, options(:machine))

    refute_received :unexpected_write
  end

  defp input,
    do: %{
      "endpoint" => @endpoint,
      "revision" => "draft",
      "auth_method" => "own_client",
      "credentials" => %{
        "grant_type" => "authorization_code",
        "client_id" => "registered",
        "client_auth_method" => "client_secret_basic",
        "client_secret" => "private-secret",
        "headers" => [%{"name" => "X-Workspace", "value" => "workspace"}],
        "authorization_parameters" => [%{"name" => "prompt", "value" => "consent"}]
      }
    }

  defp options(mode \\ :ordinary) do
    owner = self()

    [
      dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end,
      request_fun: fn _, _, _, _ ->
        send(owner, :unexpected_write)
        {:error, :unexpected}
      end,
      http_client: fn uri, _, _ ->
        send(owner, {:discovered, uri.path})

        {status, body} =
          cond do
            uri.path == "/mcp" ->
              {401, %{}}

            uri.host == "mcp.example.test" and mode == :missing ->
              {404, %{}}

            uri.host == "mcp.example.test" and mode == :malformed ->
              {200,
               %{"resource" => "https://other.test/mcp", "authorization_servers" => [@issuer]}}

            uri.host == "mcp.example.test" ->
              {200,
               %{
                 "resource" => @endpoint,
                 "authorization_servers" =>
                   if(mode == :multiple, do: [@issuer, "https://other.test"], else: [@issuer]),
                 "scopes_supported" => ["tools:read"]
               }}

            mode == :machine ->
              {200,
               %{
                 "issuer" => @issuer,
                 "token_endpoint" => @issuer <> "/token",
                 "grant_types_supported" => ["client_credentials"],
                 "token_endpoint_auth_methods_supported" => ["client_secret_basic"]
               }}

            true ->
              {200,
               %{
                 "issuer" => @issuer,
                 "authorization_endpoint" => @issuer <> "/authorize",
                 "token_endpoint" => @issuer <> "/token",
                 "grant_types_supported" => ["authorization_code", "refresh_token"],
                 "token_endpoint_auth_methods_supported" => ["client_secret_basic"],
                 "response_types_supported" => ["code"],
                 "code_challenge_methods_supported" => ["S256"],
                 "authorization_response_iss_parameter_supported" => true
               }}
          end

        {:ok, %{status: status, headers: [], body: JSON.encode!(body)}}
      end
    ]
  end

  defp flush_discovery do
    receive do
      {:discovered, _} -> flush_discovery()
    after
      0 -> :ok
    end
  end
end
