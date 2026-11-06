defmodule Vxpipe.Console.MCPOAuthPreparationTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Console.MCPOAuthPreparation

  test "preflight and OAuth preparation honor their configured bounded runner" do
    tasks = start_supervised!({Task.Supervisor, name: nil})

    runner =
      start_supervised!({Vxpipe.MCP.PreflightRunner, name: nil, task_supervisor: tasks, limit: 0})

    options = [preflight_runner: runner]

    input = %{
      "endpoint" => "https://mcp.example.test/mcp",
      "auth_method" => "cimd",
      "revision" => "draft"
    }

    assert {:error, :mcp_connection_busy} =
             MCPOAuthPreparation.prepare(
               options,
               "bounded-preparation",
               input,
               "https://console.example.test"
             )

    assert {:error, :mcp_connection_busy} =
             Vxpipe.Console.MCPPreflight.discover(
               options,
               "bounded-preflight",
               Map.delete(input, "auth_method")
             )
  end

  test "Own-client configuration is preserved privately for callback and renewal" do
    endpoint = "https://mcp.example.test/mcp"
    issuer = "https://auth.example.test"

    options = [
      dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end,
      http_client: fn uri, _, _ ->
        {status, body} =
          cond do
            uri.path == "/mcp" ->
              {401, %{}}

            uri.host == "mcp.example.test" ->
              {200, %{"resource" => endpoint, "authorization_servers" => [issuer]}}

            true ->
              {200,
               %{
                 "issuer" => issuer,
                 "authorization_endpoint" => issuer <> "/authorize",
                 "token_endpoint" => issuer <> "/token",
                 "token_endpoint_auth_methods_supported" => ["client_secret_basic"],
                 "response_types_supported" => ["code"],
                 "code_challenge_methods_supported" => ["S256"],
                 "authorization_response_iss_parameter_supported" => true
               }}
          end

        {:ok, %{status: status, headers: [], body: JSON.encode!(body)}}
      end
    ]

    values = %{
      "grant_type" => "authorization_code",
      "client_id" => "registered",
      "client_auth_method" => "client_secret_basic",
      "client_secret" => "private-client-secret",
      "audience" => "calendar-api",
      "authorization_parameters" => [%{"name" => "prompt", "value" => "consent"}],
      "token_parameters" => [%{"name" => "organization", "value" => "private-org"}],
      "headers" => [%{"name" => "X-Workspace", "value" => "private-workspace"}]
    }

    input = %{
      "endpoint" => endpoint,
      "revision" => "draft",
      "auth_method" => "own_client",
      "credentials" => values
    }

    assert {:ok, prepared} =
             MCPOAuthPreparation.prepare(
               options,
               "own-client-preparation",
               input,
               "https://console.example.test"
             )

    for field <- ~w(grant_type audience authorization_parameters token_parameters headers) do
      assert prepared.secrets[field] == values[field]
    end

    assert prepared.secrets["registration_method"] == "own_client"
    assert prepared.secrets["client_secret"] == "private-client-secret"
    assert prepared.secrets["code_verifier"]
    refute inspect(prepared) =~ "private"
  end

  test "real protocol composition projects all redemption inputs privately" do
    endpoint = "https://mcp.example.test/mcp"
    issuer = "https://auth.example.test"

    options = [
      dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end,
      http_client: fn uri, _, _ ->
        {status, body} =
          cond do
            uri.path == "/mcp" ->
              {401, %{}}

            uri.host == "mcp.example.test" ->
              {200, %{"resource" => endpoint, "authorization_servers" => [issuer]}}

            true ->
              {200,
               %{
                 "issuer" => issuer,
                 "authorization_endpoint" => issuer <> "/authorize",
                 "token_endpoint" => issuer <> "/token",
                 "client_id_metadata_document_supported" => true,
                 "token_endpoint_auth_methods_supported" => ["none"],
                 "response_types_supported" => ["code"],
                 "code_challenge_methods_supported" => ["S256"],
                 "authorization_response_iss_parameter_supported" => true
               }}
          end

        {:ok, %{status: status, headers: [], body: JSON.encode!(body)}}
      end
    ]

    assert {:ok, prepared} =
             MCPOAuthPreparation.prepare(
               options,
               "preparation-test-tenant",
               %{"endpoint" => endpoint, "auth_method" => "cimd", "revision" => "draft"},
               "https://console.example.test"
             )

    assert prepared.attributes.resource == endpoint
    assert prepared.attributes.issuer == issuer
    assert prepared.secrets["token_endpoint"] == issuer <> "/token"
    assert prepared.secrets["auth_method"] == "none"
    assert prepared.secrets["issuer_response_required"]
    assert byte_size(prepared.secrets["code_verifier"]) >= 43
    refute inspect(prepared) =~ prepared.secrets["code_verifier"]

    assert URI.decode_query(URI.parse(prepared.authorization_url).query)["state"] ==
             prepared.attributes.state
  end

  test "DCR preparation preserves secret expiry for the encrypted attempt" do
    endpoint = "https://mcp.example.test/mcp"
    issuer = "https://auth.example.test"

    options = [
      request_fun: fn _, _, _, _ ->
        {:ok,
         {{~c"HTTP/1.1", 201, ~c"Created"}, [],
          JSON.encode!(%{
            "client_id" => "registered",
            "client_secret" => "private-secret",
            "client_secret_expires_at" => 0,
            "token_endpoint_auth_method" => "client_secret_basic",
            "redirect_uris" => ["https://console.example.test/oauth/mcp/callback"]
          })}}
      end,
      dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end,
      http_client: fn uri, _, _ ->
        {status, body} =
          cond do
            uri.path == "/mcp" ->
              {401, %{}}

            uri.host == "mcp.example.test" ->
              {200, %{"resource" => endpoint, "authorization_servers" => [issuer]}}

            true ->
              {200,
               %{
                 "issuer" => issuer,
                 "authorization_endpoint" => issuer <> "/authorize",
                 "token_endpoint" => issuer <> "/token",
                 "registration_endpoint" => issuer <> "/register",
                 "token_endpoint_auth_methods_supported" => ["client_secret_basic"],
                 "response_types_supported" => ["code"],
                 "code_challenge_methods_supported" => ["S256"],
                 "authorization_response_iss_parameter_supported" => true
               }}
          end

        {:ok, %{status: status, headers: [], body: JSON.encode!(body)}}
      end
    ]

    assert {:ok, prepared} =
             MCPOAuthPreparation.prepare(
               options,
               "dcr-preparation-test-tenant",
               %{"endpoint" => endpoint, "auth_method" => "dcr", "revision" => "draft"},
               "https://console.example.test"
             )

    assert prepared.attributes.resource == endpoint
    assert prepared.attributes.issuer == issuer
    assert prepared.secrets["token_endpoint"] == issuer <> "/token"
    assert prepared.secrets["auth_method"] == "client_secret_basic"
    assert prepared.secrets["client_secret_expires_at"] == 0
    assert prepared.secrets["registration_method"] == "dcr"
    assert prepared.secrets["redirect_uri"] == "https://console.example.test/oauth/mcp/callback"
    assert prepared.secrets["issuer_response_required"]
    assert byte_size(prepared.secrets["code_verifier"]) >= 43
    refute inspect(prepared) =~ prepared.secrets["code_verifier"]

    assert URI.decode_query(URI.parse(prepared.authorization_url).query)["state"] ==
             prepared.attributes.state
  end
end
