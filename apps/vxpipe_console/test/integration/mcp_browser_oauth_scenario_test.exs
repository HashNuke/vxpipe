defmodule Vxpipe.Console.MCPBrowserOAuthScenarioTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Console.Test.{MCPBrowserScenario, OutboundMCPOAuthServer}
  alias Vxpipe.MCP.{OAuthPreparation, OAuthTokenExchange, OwnOAuthPreparation, Preflight}
  alias Vxpipe.MCP.StaticConfiguration
  @moduletag :integration

  for method <- ~w(none client_secret_basic client_secret_post private_key_jwt) do
    test "provisioned #{method} browser client completes authorization and MCP discovery" do
      {:ok, scenario} =
        MCPBrowserScenario.new("own_client", client_auth_method: unquote(method))

      {peer, options} = start_peer(scenario)
      input = input("own_client") |> Map.put("credentials", scenario.credentials)

      assert {:ok, discovery} =
               Preflight.discover("browser", Map.take(input, ~w(endpoint revision)), options)

      assert discovery.suggested_method == "own_client"
      assert OutboundMCPOAuthServer.count(peer, {"POST", "/token"}) == 0

      assert {:ok, configuration} =
               OwnOAuthPreparation.configuration(input, OutboundMCPOAuthServer.origin(), options)

      assert {:ok, prepared} =
               OAuthPreparation.prepare(input, OutboundMCPOAuthServer.origin(), options)

      callback = authorize(peer, prepared)

      request =
        Map.merge(configuration.token_request, %{
          code: callback["code"],
          code_verifier: prepared.authorization.code_verifier,
          redirect_uri: prepared.authorization.redirect_uri
        })

      assert {:ok, token} = OAuthTokenExchange.exchange(Map.delete(request, :scope), options)
      assert_mcp(token, options)
      assert OutboundMCPOAuthServer.count(peer, {"POST", "/register"}) == 0
      assert OutboundMCPOAuthServer.count(peer, {"POST", "/token"}) == 1
    end
  end

  for method <- ~w(client_secret_basic client_secret_post private_key_jwt) do
    test "provisioned #{method} machine client connects without browser or registration" do
      {:ok, scenario} = MCPBrowserScenario.new("machine", client_auth_method: unquote(method))
      {peer, options} = start_peer(scenario)
      input = input("own_client") |> Map.put("credentials", scenario.credentials)

      assert {:ok, discovery} =
               Preflight.discover("browser", Map.take(input, ~w(endpoint revision)), options)

      assert discovery.supported_grants == ["client_credentials"]

      assert {:ok, configuration} =
               OwnOAuthPreparation.configuration(input, OutboundMCPOAuthServer.origin(), options)

      assert {:ok, token} =
               OAuthTokenExchange.client_credentials(
                 configuration.token_request,
                 configuration.metadata,
                 options
               )

      assert token.refresh_token == nil
      assert_mcp(token, options)
      assert OutboundMCPOAuthServer.count(peer, {"POST", "/register"}) == 0
      assert OutboundMCPOAuthServer.count(peer, {"GET", "/authorize"}) == 0
      assert OutboundMCPOAuthServer.count(peer, {"POST", "/token"}) == 1
    end
  end

  test "protected DCR requires the startup token before issuing a working client" do
    {:ok, scenario} = MCPBrowserScenario.new("protected_dcr")
    {peer, options} = start_peer(scenario)
    origin = OutboundMCPOAuthServer.origin()

    for token <- [nil, "incorrect-fixture-token"] do
      input = input("dcr")
      input = if token, do: Map.put(input, "initial_access_token", token), else: input
      assert {:error, _} = OAuthPreparation.prepare(input, origin, options)
      assert Agent.get(peer, &map_size(&1.clients)) == 0
    end

    input = Map.merge(input("dcr"), scenario.credentials)
    assert {:ok, prepared} = OAuthPreparation.prepare(input, origin, options)
    callback = authorize(peer, prepared)

    assert {:ok, token} =
             OAuthTokenExchange.exchange(
               %{
                 token_endpoint: prepared.token_endpoint,
                 client_id: prepared.client.client_id,
                 client_secret: prepared.client.client_secret,
                 auth_method: prepared.client.auth_method,
                 code: callback["code"],
                 code_verifier: prepared.authorization.code_verifier,
                 redirect_uri: prepared.authorization.redirect_uri,
                 resource: OutboundMCPOAuthServer.resource()
               },
               options
             )

    assert_mcp(token, options)
    assert OutboundMCPOAuthServer.count(peer, {"POST", "/register"}) == 3
  end

  test "invalid client methods fail at startup, including public machine clients" do
    assert {:error, :unsupported_browser_scenario} =
             MCPBrowserScenario.new("own_client", client_auth_method: "invalid")

    assert {:error, :unsupported_browser_scenario} =
             MCPBrowserScenario.new("machine", client_auth_method: "none")
  end

  defp input(method),
    do: %{
      "endpoint" => OutboundMCPOAuthServer.resource(),
      "revision" => "browser",
      "auth_method" => method
    }

  defp start_peer(scenario) do
    peer = start_supervised!({Agent, fn -> scenario.state end})

    server =
      start_supervised!(
        {Bandit, plug: {OutboundMCPOAuthServer, peer}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    OutboundMCPOAuthServer.configure(peer, %{base: "http://127.0.0.1:#{port}"})
    {peer, OutboundMCPOAuthServer.options(peer)}
  end

  defp authorize(peer, prepared) do
    response = OutboundMCPOAuthServer.authorize(peer, prepared.authorization.authorization_url)
    assert response.status == 303
    [location] = Req.Response.get_header(response, "location")
    URI.decode_query(URI.parse(location).query)
  end

  defp assert_mcp(token, options) do
    assert {:ok, configuration} =
             StaticConfiguration.new(%{
               "endpoint" => OutboundMCPOAuthServer.resource(),
               "auth_method" => "bearer",
               "credentials" => %{"token" => token.access_token}
             })

    check = Keyword.fetch!(options, :connection_check)

    assert {:ok, %{server_name: "Fixture calendar", catalog: [_]}} =
             check.("browser", configuration)
  end
end
