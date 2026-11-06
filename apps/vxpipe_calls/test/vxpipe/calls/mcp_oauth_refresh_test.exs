defmodule Vxpipe.Calls.MCPOAuthRefreshTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.MCPOAuthRefresh
  alias Vxpipe.Calls.Test.MCPRefreshFixture

  test "durable claim precedes network work and token rotation" do
    tokens = %{"access_token" => "private"}
    assert :ok = MCPOAuthRefresh.refresh("tenant", "connection", 2, 3, options({:ok, tokens}))
    assert_receive {:claimed, "tenant", "connection", 2, 3}
    assert_receive :refreshed
    assert_receive {:committed, "tenant", "connection", 2, "claim", ^tokens}
    refute_received {:failed, _, _, _, _}
  end

  test "failed or ambiguous exchange fences grant without retrying or exposing provider errors" do
    assert {:error, :oauth_reconnect_required} =
             MCPOAuthRefresh.refresh(
               "tenant",
               "connection",
               2,
               3,
               options({:error, {:provider, "private"}})
             )

    assert_receive :refreshed
    assert_receive {:failed, "tenant", "connection", 2, "claim"}
    refute_received :refreshed
    refute_received {:committed, _, _, _, _, _}
  end

  defp options(result),
    do: [
      mcp_oauth_grant_repository: {MCPRefreshFixture, {self(), result}},
      mcp_oauth_refresh: {MCPRefreshFixture, {self(), result}}
    ]
end
