defmodule Vxpipe.Console.MCPSavedPreflightTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Console.MCPPreflight
  @endpoint "https://mcp.example.test/mcp"
  @issuer "https://auth.example.test"
  @origin "https://console.example.test"

  setup do
    tasks = start_supervised!({Task.Supervisor, []})

    runner =
      start_supervised!(
        {Vxpipe.MCP.PreflightRunner, name: nil, task_supervisor: tasks, interval: 0}
      )

    entry = %{
      "directory_id" => "public",
      "integration_id" => "calendar",
      "revision" => 1,
      "endpoint" => @endpoint,
      "name" => "Calendar",
      "authentication" => %{"type" => "oauth2", "registration" => "discover"}
    }

    registration = %{
      "registration_method" => "dcr",
      "client_id" => "registered",
      "auth_method" => "none",
      "issuer" => @issuer,
      "resource" => @endpoint,
      "redirect_uri" => @origin <> "/oauth/mcp/callback",
      "scopes" => ["tools.read"]
    }

    metadata = %{
      "issuer" => @issuer,
      "authorization_endpoint" => @issuer <> "/authorize",
      "token_endpoint" => @issuer <> "/token",
      "token_endpoint_auth_methods_supported" => ["none", "client_secret_basic"],
      "authorization_response_iss_parameter_supported" => true,
      "code_challenge_methods_supported" => ["S256"],
      "response_types_supported" => ["code"]
    }

    %{runner: runner, entry: entry, registration: registration, metadata: metadata}
  end

  test "saved DCR is reusable without an advertised registration endpoint and never sent during discovery",
       data do
    assert {:ok, result} = discover(data)
    assert result.oauth_registration == %{method: "dcr", reusable: true}
    assert result.listing == data.entry

    assert result.oauth_client == %{
             callback_url: @origin <> "/oauth/mcp/callback",
             client_id: @origin <> "/oauth/client-metadata.json"
           }

    refute inspect(result) =~ "registered"
  end

  test "fresh method selection handles unavailable, expired, scope-expanded and changed registrations",
       data do
    for registration <- [
          %{},
          %{data.registration | "issuer" => "https://other.example.test"},
          %{data.registration | "scopes" => []},
          Map.merge(data.registration, %{
            "auth_method" => "client_secret_basic",
            "client_secret" => "synthetic",
            "client_secret_expires_at" => 1
          })
        ] do
      assert {:ok, result} = discover(%{data | registration: registration})
      assert result.oauth_registration == %{method: "own_client", reusable: false}
      refute inspect(result) =~ "synthetic"
    end

    metadata = Map.merge(data.metadata, %{"registration_endpoint" => @issuer <> "/register"})
    assert {:ok, result} = discover(%{data | registration: %{}, metadata: metadata})
    assert result.oauth_registration == %{method: "dcr", reusable: false}
  end

  test "preregistered and missing-resource recipes retain the manual client path", data do
    entry = put_in(data.entry, ["authentication", "registration"], "preregistered")
    assert {:ok, result} = discover(%{data | entry: entry})
    assert result.oauth_registration == %{method: "own_client", reusable: false}
    assert {:ok, result} = discover(data, true)
    assert result.oauth_registration == %{method: "own_client", reusable: false}
  end

  test "a listed browser recipe cannot be selected from machine-only capabilities", data do
    metadata = Map.put(data.metadata, "grant_types_supported", ["client_credentials"])
    assert {:ok, result} = discover(%{data | metadata: metadata})
    assert result.outcome == :unsupported_oauth
    refute Map.has_key?(result, :oauth_registration)
  end

  defp discover(data, missing_resource \\ false) do
    options = [
      preflight_runner: data.runner,
      listing_options: [
        fetcher: fn _, _ -> flunk("saved discovery must not read the directory") end
      ],
      dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end,
      http_client: fn uri, _address, settings ->
        refute inspect(settings) =~ "registered"
        refute inspect(settings) =~ "synthetic"

        {status, body} =
          cond do
            uri.host == "auth.example.test" ->
              {200, data.metadata}

            uri.path == "/mcp" ->
              {401, %{}}

            missing_resource ->
              {404, %{}}

            true ->
              {200,
               %{
                 "resource" => @endpoint,
                 "authorization_servers" => [@issuer],
                 "scopes_supported" => ["tools.read"]
               }}
          end

        {:ok, %{status: status, headers: [], body: JSON.encode!(body)}}
      end,
      request_fun: fn _, _, _, _ -> flunk("discovery must not register or exchange tokens") end
    ]

    input = %{"endpoint" => @endpoint, "revision" => "draft", "issuer" => @issuer}
    MCPPreflight.discover_saved(options, "tenant", input, @origin, data.registration, data.entry)
  end
end
