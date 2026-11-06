defmodule Vxpipe.Console.MCPOAuthRefreshTest do
  use ExUnit.Case, async: true

  test "expired registration cannot send its client secret during refresh" do
    claim = %Vxpipe.Calls.ResolvedMCPRefresh{
      id: "claim",
      grant_revision: 1,
      secrets: %{
        "token_endpoint" => "https://auth.example.test/token",
        "client_id" => "client",
        "auth_method" => "client_secret_post",
        "client_secret" => "private-secret",
        "client_secret_expires_at" => 1,
        "refresh_token" => "refresh",
        "resource" => "https://mcp.example.test/mcp"
      }
    }

    owner = self()

    options = [
      dns_resolver: fn _, _ ->
        send(owner, :unexpected_dns)
        {:error, :nxdomain}
      end
    ]

    assert {:error, :invalid_oauth_token_request} =
             Vxpipe.Console.MCPOAuthRefresh.refresh(options, claim)

    refute_received :unexpected_dns
  end

  test "refresh projects token fields and omits absent rotating token" do
    claim = %Vxpipe.Calls.ResolvedMCPRefresh{
      id: "claim",
      grant_revision: 1,
      secrets: %{
        "token_endpoint" => "https://auth.example.test/token",
        "client_id" => "client",
        "auth_method" => "none",
        "refresh_token" => "refresh",
        "resource" => "https://mcp.example.test/mcp"
      }
    }

    options = [
      dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end,
      request_fun: fn _, _, _, _ ->
        {:ok,
         {{~c"HTTP/1.1", 200, ~c"OK"}, [],
          JSON.encode!(%{
            "access_token" => "new-access",
            "token_type" => "Bearer",
            "expires_in" => 300
          })}}
      end
    ]

    assert {:ok, tokens} = Vxpipe.Console.MCPOAuthRefresh.refresh(options, claim)
    assert tokens["access_token"] == "new-access"
    assert {:ok, _, _} = DateTime.from_iso8601(tokens["expires_at"])
    refute Map.has_key?(tokens, "refresh_token")
    refute Map.has_key?(tokens, "client_id")
  end

  test "renewal request time cannot extend the returned token lifetime" do
    clock = start_supervised!({Agent, fn -> ~U[2026-11-07 00:00:00Z] end})

    claim = %Vxpipe.Calls.ResolvedMCPRefresh{
      id: "claim",
      grant_revision: 1,
      secrets: %{
        "token_endpoint" => "https://auth.example.test/token",
        "client_id" => "client",
        "auth_method" => "none",
        "refresh_token" => "refresh",
        "resource" => "https://mcp.example.test/mcp"
      }
    }

    options = [
      now: fn -> Agent.get(clock, & &1) end,
      dns_resolver: fn _, _ -> {:ok, [{93, 184, 216, 34}]} end,
      request_fun: fn _, _, _, _ ->
        Agent.update(clock, &DateTime.add(&1, 45))

        {:ok,
         {{~c"HTTP/1.1", 200, ~c"OK"}, [],
          JSON.encode!(%{
            "access_token" => "new-access",
            "token_type" => "Bearer",
            "expires_in" => 300
          })}}
      end
    ]

    assert {:ok, tokens} = Vxpipe.Console.MCPOAuthRefresh.refresh(options, claim)
    assert tokens["expires_at"] == "2026-11-07T00:05:00Z"
  end
end
