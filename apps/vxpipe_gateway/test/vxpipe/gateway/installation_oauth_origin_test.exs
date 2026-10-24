defmodule Vxpipe.Gateway.InstallationOAuthOriginTest do
  use ExUnit.Case, async: true
  import Plug.Test
  alias Vxpipe.Gateway.OAuth.Endpoint
  alias Vxpipe.Gateway.MCP.Endpoint, as: MCPEndpoint
  alias Vxpipe.Gateway.TestInstallationOrigin, as: Origin

  defp options do
    [
      enabled: true,
      issuer: "https://old.example.test",
      resource: "https://old.example.test/mcp",
      allowed_hosts: ["old.example.test"],
      allowed_origins: ["https://old.example.test"],
      public_url_provider: Origin
    ]
  end

  test "initialized discovery and MCP challenges follow changes to the installed origin" do
    oauth = Endpoint.init(options())
    mcp = MCPEndpoint.init(options())

    for host <- ["first.example.test", "second.example.test"] do
      Process.put(Origin, {:ok, "https://" <> host})

      conn =
        Endpoint.call(conn(:get, "https://#{host}/.well-known/oauth-authorization-server"), oauth)

      assert conn.status == 200

      assert JSON.decode!(conn.resp_body)["authorization_endpoint"] ==
               "https://#{host}/oauth/authorize"

      challenge = MCPEndpoint.call(conn(:post, "https://#{host}/mcp", "{}"), mcp)
      assert challenge.status == 401

      assert Plug.Conn.get_resp_header(challenge, "www-authenticate") |> hd() =~
               "https://#{host}/.well-known/oauth-protected-resource/mcp"
    end

    Process.put(Origin, {:error, :unavailable})

    assert Endpoint.call(
             conn(:get, "https://old.example.test/.well-known/oauth-authorization-server"),
             oauth
           ).status == 503

    assert MCPEndpoint.call(conn(:post, "https://old.example.test/mcp", "{}"), mcp).status == 503
  end

  test "an explicitly configured separate MCP resource remains unchanged" do
    Process.put(Origin, {:ok, "https://new.example.test"})

    options =
      options()
      |> Keyword.put(:resource, "https://gateway.example.test/mcp")
      |> Keyword.put(:resource_override, true)

    response =
      Endpoint.call(
        conn(:get, "https://new.example.test/.well-known/oauth-protected-resource/mcp"),
        Endpoint.init(options)
      )

    assert JSON.decode!(response.resp_body)["resource"] == "https://gateway.example.test/mcp"
  end

  test "a separate resource retains its host allowlist when the installation issuer moves" do
    options =
      options()
      |> Keyword.put(:resource, "https://gateway.example.test/mcp")
      |> Keyword.put(:resource_override, true)
      |> Keyword.put(:allowed_hosts, ["gateway.example.test"])
      |> Keyword.put(:allowed_origins, ["https://gateway.example.test"])

    mcp = MCPEndpoint.init(options)
    Process.put(Origin, {:ok, "https://new.example.test"})

    assert MCPEndpoint.call(conn(:post, "https://gateway.example.test/mcp", "{}"), mcp).status ==
             401

    assert MCPEndpoint.call(conn(:post, "https://new.example.test/mcp", "{}"), mcp).status == 421
  end
end
