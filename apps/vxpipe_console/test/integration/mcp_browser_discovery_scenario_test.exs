defmodule Vxpipe.Console.MCPBrowserDiscoveryScenarioTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Console.Test.{MCPBrowserScenario, OutboundMCPOAuthServer}
  alias Vxpipe.MCP.{OAuthPreparation, Preflight}
  @moduletag :integration

  test "partial metadata preserves issuer context and succeeds on explicit retry" do
    {peer, options} = start_peer("partial")
    assert {:ok, partial} = Preflight.discover("browser", input(), options)
    assert partial.outcome == :partial
    assert partial.issuer == OutboundMCPOAuthServer.issuer()
    assert partial.suggested_method == nil
    assert_read_only(peer)

    assert {:ok, recovered} = Preflight.discover("browser", input(), options)
    assert recovered.outcome == :oauth
    assert recovered.suggested_method == "cimd"
    assert_read_only(peer)
  end

  test "multiple issuers require selection and permit recovery from an unavailable issuer" do
    {peer, options} = start_peer("multiple_issuers")
    issuer = OutboundMCPOAuthServer.issuer()
    assert {:ok, choice} = Preflight.discover("browser", input(), options)
    assert choice.outcome == :issuer_required
    assert choice.issuers == [issuer, issuer <> "/unavailable"]

    assert OutboundMCPOAuthServer.count(peer, {"GET", "/.well-known/oauth-authorization-server"}) ==
             0

    assert {:ok, partial} =
             Preflight.discover(
               "browser",
               Map.put(input(), "issuer", issuer <> "/unavailable"),
               options
             )

    assert partial.outcome == :partial
    assert partial.issuer == issuer <> "/unavailable"

    assert {:ok, recovered} =
             Preflight.discover("browser", Map.put(input(), "issuer", issuer), options)

    assert recovered.outcome == :oauth
    assert recovered.suggested_method == "cimd"
    assert_read_only(peer)
  end

  test "unsupported OAuth metadata stays explicit and cannot prepare authorization" do
    {peer, options} = start_peer("unsupported")
    assert {:ok, unsupported} = Preflight.discover("browser", input(), options)
    assert unsupported.outcome == :unsupported_oauth
    assert unsupported.supported_grants == []
    assert unsupported.suggested_method == nil

    assert {:error, :unsupported_oauth_capabilities} =
             OAuthPreparation.prepare(
               Map.put(input(), "auth_method", "cimd"),
               OutboundMCPOAuthServer.origin(),
               options
             )

    assert_read_only(peer)
  end

  defp input,
    do: %{"endpoint" => OutboundMCPOAuthServer.resource(), "revision" => "discovery"}

  defp start_peer(mode) do
    {:ok, scenario} = MCPBrowserScenario.new(mode)
    peer = start_supervised!({Agent, fn -> scenario.state end})

    server =
      start_supervised!(
        {Bandit, plug: {OutboundMCPOAuthServer, peer}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    OutboundMCPOAuthServer.configure(peer, %{base: "http://127.0.0.1:#{port}"})
    {peer, OutboundMCPOAuthServer.options(peer)}
  end

  defp assert_read_only(peer) do
    for key <- [{"POST", "/register"}, {"POST", "/token"}, "initialize", "tools/call"],
        do: assert(OutboundMCPOAuthServer.count(peer, key) == 0)
  end
end
