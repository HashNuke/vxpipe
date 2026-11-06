defmodule Vxpipe.Console.MCPOAuthCompletionTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Console.MCPOAuthCompletion
  alias Vxpipe.MCP.OAuthCallback

  defp attempt do
    %Vxpipe.Calls.ResolvedMCPOAuthAttempt{
      attempt: %{
        connection_id: "connection",
        generation: 1,
        issuer: "https://auth.example.test",
        resource: "https://mcp.example.test/mcp",
        redirect_uri: "https://console.example.test/oauth/mcp/callback"
      },
      secrets: %{
        "code_verifier" => String.duplicate("v", 43),
        "client_id" => "client",
        "auth_method" => "none",
        "token_endpoint" => "https://auth.example.test/token",
        "issuer_response_required" => true
      }
    }
  end

  defp callback(issuer \\ "https://auth.example.test"),
    do: %OAuthCallback{state: String.duplicate("s", 43), code: "code", issuer: issuer}

  test "token exchange precedes initialization and returns a private OAuth connection" do
    owner = self()

    opts =
      options(owner, fn tenant, configuration ->
        send(owner, {:checked, tenant, configuration.auth_method, configuration.secrets})
        {:ok, %{server_name: "Calendar", catalog: []}}
      end)

    assert {:ok, resolved} = MCPOAuthCompletion.complete(opts, "tenant", callback(), attempt())
    assert_receive :exchanged
    assert_receive {:checked, "tenant", "bearer", %{"token" => "private-access", "headers" => []}}
    assert resolved.connection.auth_method == "oauth"
    assert resolved.connection.server_name == "Calendar"
    assert resolved.connection.id == "connection"
    assert resolved.secrets["access_token"] == "private-access"
    assert resolved.secrets["refresh_token"] == "private-refresh"
    refute inspect(resolved) =~ "private-access"
  end

  test "issuer mismatch stops before any exchange or initialization" do
    opts = options(self(), fn _, _ -> flunk("unexpected check") end)

    assert {:error, :oauth_issuer_mismatch} =
             MCPOAuthCompletion.complete(
               opts,
               "tenant",
               callback("https://other.test"),
               attempt()
             )

    refute_received :exchanged
  end

  test "MCP checking does not extend the token lifetime" do
    received_at = ~U[2026-11-07 00:00:00Z]
    clock = start_supervised!({Agent, fn -> received_at end})

    opts =
      options(self(), fn _, _ ->
        Agent.update(clock, &DateTime.add(&1, 120))
        {:ok, %{server_name: "Tools", catalog: []}}
      end)

    opts = Keyword.put(opts, :now, fn -> Agent.get(clock, & &1) end)
    assert {:ok, resolved} = MCPOAuthCompletion.complete(opts, "tenant", callback(), attempt())
    assert resolved.secrets["expires_at"] == "2026-11-07T00:05:00Z"
  end

  test "failed MCP initialization does not produce a connected record" do
    opts = options(self(), fn _, _ -> {:error, {:private, "token"}} end)

    assert {:error, :mcp_connection_failed} =
             MCPOAuthCompletion.complete(opts, "tenant", callback(), attempt())
  end

  test "secret expiry during consent stops before token redemption" do
    original = attempt()

    secrets =
      Map.merge(original.secrets, %{
        "auth_method" => "client_secret_basic",
        "client_secret" => "private-secret",
        "client_secret_expires_at" => 1
      })

    owner = self()

    opts = [
      dns_resolver: fn _, _ ->
        send(owner, :unexpected_dns)
        {:error, :nxdomain}
      end
    ]

    assert {:error, :oauth_completion_failed} =
             MCPOAuthCompletion.complete(opts, "tenant", callback(), %{
               original
               | secrets: secrets
             })

    refute_received :unexpected_dns
  end

  test "successful completion retains client expiry for later refresh" do
    original = attempt()
    expiry = System.os_time(:second) + 3600

    secrets =
      Map.merge(original.secrets, %{
        "auth_method" => "client_secret_basic",
        "client_secret" => "private-secret",
        "client_secret_expires_at" => expiry
      })

    opts = options(self(), fn _, _ -> {:ok, %{server_name: "Tools", catalog: []}} end)

    assert {:ok, resolved} =
             MCPOAuthCompletion.complete(opts, "tenant", callback(), %{
               original
               | secrets: secrets
             })

    assert resolved.secrets["client_secret_expires_at"] == expiry
    assert_receive :exchanged
  end

  defp options(owner, check),
    do: [
      dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end,
      request_fun: fn _, _, _, _ ->
        send(owner, :exchanged)

        {:ok,
         {{~c"HTTP/1.1", 200, ~c"OK"}, [],
          JSON.encode!(%{
            "access_token" => "private-access",
            "refresh_token" => "private-refresh",
            "token_type" => "Bearer",
            "expires_in" => 300
          })}}
      end,
      connection_check: check
    ]
end
