defmodule Vxpipe.Console.MCPBrowserPeerTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Console.Test.OutboundMCPOAuthServer
  alias Vxpipe.MCP.{OAuthPreparation, OAuthTokenExchange, StaticConfiguration}
  @moduletag :integration

  for mode <- ["cimd", "dcr"] do
    test "#{mode} peer supports the browser installation's HTTPS origins" do
      mode = unquote(mode)
      peer = start_supervised!({Agent, fn -> OutboundMCPOAuthServer.initial(mode) end})

      server =
        start_supervised!(
          {Bandit, plug: {OutboundMCPOAuthServer, peer}, ip: {127, 0, 0, 1}, port: 0}
        )

      {:ok, {_address, port}} = ThousandIsland.listener_info(server)
      origin = "https://localhost:8443"
      issuer = "https://auth.example.test:9443"
      resource = "https://mcp.example.test:9443/mcp"

      OutboundMCPOAuthServer.configure(peer, %{
        base: "http://127.0.0.1:#{port}",
        origin: origin,
        issuer: issuer,
        resource: resource
      })

      options = OutboundMCPOAuthServer.options(peer)
      input = %{"endpoint" => resource, "revision" => "browser", "auth_method" => mode}
      assert {:ok, prepared} = OAuthPreparation.prepare(input, origin, options)
      assert prepared.authorization.issuer == issuer
      assert prepared.authorization.resource == resource
      assert prepared.token_endpoint == issuer <> "/token"
      response = OutboundMCPOAuthServer.authorize(peer, prepared.authorization.authorization_url)
      assert response.status == 303
      [location] = Req.Response.get_header(response, "location")
      uri = URI.parse(location)
      assert %{uri | query: nil} |> URI.to_string() == origin <> "/oauth/mcp/callback"
      callback = URI.decode_query(uri.query)
      assert callback["iss"] == issuer

      request = %{
        token_endpoint: prepared.token_endpoint,
        client_id: prepared.client.client_id,
        client_secret: prepared.client.client_secret,
        auth_method: prepared.client.auth_method,
        code: callback["code"],
        code_verifier: prepared.authorization.code_verifier,
        redirect_uri: prepared.authorization.redirect_uri,
        resource: resource
      }

      request =
        if prepared.client.auth_method == :none,
          do: Map.delete(request, :client_secret),
          else: request

      assert {:ok, token} = OAuthTokenExchange.exchange(request, options)

      assert {:ok, configuration} =
               StaticConfiguration.new(%{
                 "endpoint" => resource,
                 "auth_method" => "bearer",
                 "credentials" => %{"token" => token.access_token}
               })

      check = Keyword.fetch!(options, :connection_check)

      assert {:ok, %{server_name: "Fixture calendar", catalog: [_]}} =
               check.("browser", configuration)

      assert OutboundMCPOAuthServer.count(peer, {"POST", "/register"}) ==
               if(mode == "dcr", do: 1, else: 0)

      assert OutboundMCPOAuthServer.count(peer, {"POST", "/token"}) == 1
    end
  end
end
