defmodule Vxpipe.Console.MCPBrowserStaticPeerTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Console.Test.{MCPBrowserScenario, OutboundMCPOAuthServer}
  alias Vxpipe.MCP.{Preflight, StaticConfiguration}
  @moduletag :integration

  for mode <- ~w(none bearer headers basic) do
    test "#{mode} startup mode enforces authentication over the real protocol" do
      mode = unquote(mode)
      {:ok, scenario} = MCPBrowserScenario.new(mode)
      peer = start_supervised!({Agent, fn -> scenario.state end})

      server =
        start_supervised!(
          {Bandit, plug: {OutboundMCPOAuthServer, peer}, ip: {127, 0, 0, 1}, port: 0}
        )

      {:ok, {_address, port}} = ThousandIsland.listener_info(server)
      base = "http://127.0.0.1:#{port}"
      OutboundMCPOAuthServer.configure(peer, %{base: base})
      options = OutboundMCPOAuthServer.options(peer)
      endpoint = OutboundMCPOAuthServer.resource()

      assert {:ok, discovered} =
               Preflight.discover(
                 "browser",
                 %{"endpoint" => endpoint, "revision" => mode},
                 options
               )

      assert discovered.outcome == if(mode == "none", do: :anonymous, else: :unknown)
      assert discovered.suggested_method == if(mode == "none", do: "none", else: nil)

      assert {:ok, configuration} =
               StaticConfiguration.new(%{
                 "endpoint" => endpoint,
                 "auth_method" => mode,
                 "credentials" => scenario.credentials
               })

      check = Keyword.fetch!(options, :connection_check)

      assert {:ok, %{server_name: "Fixture calendar", catalog: [_]}} =
               check.("browser", configuration)

      for path <- [
            "/.well-known/oauth-protected-resource/mcp",
            "/.well-known/oauth-authorization-server"
          ] do
        assert Req.get!(base <> path, retry: false).status == 404
      end

      assert Req.post!(base <> "/token", form: [grant_type: "client_credentials"], retry: false).status ==
               404

      assert OutboundMCPOAuthServer.count(peer, {"POST", "/register"}) == 0

      if mode != "none" do
        for headers <- [[], wrong_credentials(mode)] do
          response =
            Req.post!(base <> "/mcp",
              headers: headers,
              json: %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/call", "params" => %{}},
              retry: false
            )

          assert response.status == 401
          refute Map.has_key?(response.body, "result")
        end

        assert OutboundMCPOAuthServer.count(peer, "tools/call") == 2
      end
    end
  end

  defp wrong_credentials("bearer"), do: [{"authorization", "Bearer fixture-wrong"}]
  defp wrong_credentials("headers"), do: [{"x-api-key", "fixture-wrong"}]

  defp wrong_credentials("basic"),
    do: [{"authorization", "Basic " <> Base.encode64("fixture-user:fixture-wrong")}]
end
