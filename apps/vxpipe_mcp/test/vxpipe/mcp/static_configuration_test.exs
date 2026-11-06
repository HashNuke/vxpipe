defmodule Vxpipe.MCP.StaticConfigurationTest do
  use ExUnit.Case, async: true
  alias Vxpipe.MCP.StaticConfiguration

  test "canonical endpoint identity preserves paths and queries without accepting URL credentials" do
    assert {:ok, config} =
             StaticConfiguration.new(%{
               "endpoint" => "https://MCP.Example.test:443/tools?region=eu",
               "auth_method" => "none",
               "credentials" => %{}
             })

    assert config.endpoint == "https://mcp.example.test/tools?region=eu"
    assert config.authentication == :none

    for endpoint <- [
          "http://mcp.example.test/mcp",
          "https://user:pass@mcp.example.test/mcp",
          "https://mcp.example.test/mcp#fragment"
        ] do
      assert {:error, :invalid_mcp_endpoint} =
               StaticConfiguration.new(%{
                 "endpoint" => endpoint,
                 "auth_method" => "none",
                 "credentials" => %{}
               })
    end
  end

  test "bearer and Basic do not inherit another authentication method's headers" do
    assert {:ok, bearer} = config("bearer", %{"token" => "synthetic-token"})

    assert {:ok, [{"authorization", "Bearer synthetic-token"}]} =
             Vxpipe.MCP.Authentication.headers(bearer.authentication)

    refute inspect(bearer) =~ "synthetic-token"
    assert {:ok, basic} = config("basic", %{"username" => "user", "password" => "password"})

    assert {:ok, [{"authorization", "Basic " <> encoded}]} =
             Vxpipe.MCP.Authentication.headers(basic.authentication)

    assert Base.decode64!(encoded) == "user:password"

    assert {:error, :invalid_mcp_authentication} =
             config("basic", %{"username" => "user", "password" => "password", "token" => "stale"})

    assert {:error, :invalid_mcp_authentication} = config("none", %{"token" => "stale"})
    assert {:error, :invalid_mcp_authentication} = config("oauth", %{})
  end

  test "credential query parameters are rejected before public endpoint persistence" do
    for query <- [
          "access_token=synthetic-secret",
          "API-Key=synthetic-secret",
          "apiKey=synthetic-secret",
          "%61pi_key=synthetic-secret",
          "token=synthetic-secret&token=other",
          "client_secret=synthetic-secret",
          "region=eu;password=synthetic-secret",
          "X-Amz-Signature=synthetic-secret",
          "key=synthetic-secret",
          "api_key%5B%5D=synthetic-secret",
          "token[0]=synthetic-secret",
          "api_key[value]=synthetic-secret",
          "token%5B0%5D=synthetic-secret",
          "api_key%5Bvalue%5D=synthetic-secret",
          "api%ZZkey=synthetic-secret",
          "%2561pi_key=synthetic-secret"
        ] do
      assert {:error, :invalid_mcp_endpoint} =
               StaticConfiguration.endpoint("https://mcp.example.test/mcp?" <> query)
    end

    assert {:ok, "https://mcp.example.test/mcp?region=eu&api-version=2&workspace=a%2Fb"} =
             StaticConfiguration.endpoint(
               "https://mcp.example.test/mcp?region=eu&api-version=2&workspace=a%2Fb"
             )
  end

  test "custom headers and extra headers cannot override managed transport or Authorization" do
    assert {:ok, headers} =
             config("headers", %{
               "headers" => [%{"name" => "X-API-Key", "value" => "synthetic-key"}]
             })

    assert {:ok, [{"x-api-key", "synthetic-key"}]} =
             Vxpipe.MCP.Authentication.headers(headers.authentication)

    for name <- ["Host", "Content-Length", "Mcp-Session-Id", "Authorization"] do
      assert {:error, :invalid_mcp_authentication} =
               config("bearer", %{
                 "token" => "token",
                 "headers" => [%{"name" => name, "value" => "override"}]
               })
    end

    assert {:error, :invalid_mcp_authentication} =
             config("headers", %{"headers" => [%{"name" => "X-Key", "value" => "a\r\nb"}]})

    assert {:error, :invalid_mcp_authentication} =
             config("basic", %{"username" => "user:name", "password" => "password"})
  end

  test "request input cannot choose runtime adapters, private hosts or fixture profiles" do
    input = %{
      "endpoint" => "https://mcp.example.test/mcp",
      "auth_method" => "none",
      "credentials" => %{}
    }

    for field <-
          ~w(runtime protocol runtime_options allowed_private_hosts test_mode supervisor timeout) do
      assert {:error, :invalid_mcp_configuration} =
               StaticConfiguration.new(Map.put(input, field, true))
    end
  end

  defp config(method, credentials),
    do:
      StaticConfiguration.new(%{
        "endpoint" => "https://mcp.example.test/mcp",
        "auth_method" => method,
        "credentials" => credentials
      })
end
