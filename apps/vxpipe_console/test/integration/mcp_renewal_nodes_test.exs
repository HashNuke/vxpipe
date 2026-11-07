defmodule Vxpipe.Console.MCPRenewalNodesTest do
  use Vxpipe.Console.Test.MCPRuntimeNodeCase, async: false

  for grant <- ["authorization_code", "client_credentials"],
      cause <- [:caller_cancellation, :runner_restart] do
    @tag grant: grant
    test "#{cause} fences a held #{grant} response across nodes and permits fresh work", data do
      assert {:ok, before} = saved(data)
      hold(data, true)
      assert :started = rpc(data.first, :start_renewal, [data.tenant, data.id])
      assert_receive {:node_token_response, request, 200}, 5_000

      case unquote(cause) do
        :caller_cancellation ->
          assert :cancelled = rpc(data.first, :cancel_renewal)

        :runner_restart ->
          assert {:restarted, {:error, :oauth_reconnect_required}} =
                   rpc(data.first, :restart_renewal_runner)
      end

      send(request, :release_token)
      assert_receive {:node_token_released, ^request}, 5_000
      assert_receive {:node_token_finished, ^request}, 5_000
      assert_fenced(data, before)
      assert tokens(data) == 1

      hold(data, false)
      assert :ok = rpc(data.first, :refresh, [data.other_tenant, data.other_id, 1])
      assert_receive {:node_token_response, fresh, 200}, 5_000
      assert_receive {:node_token_finished, ^fresh}, 5_000
      assert tokens(data) == 2
      assert {:ok, current} = saved(data)
      assert Map.delete(current.secrets, "refresh_claim") == before.secrets
    end
  end

  defp assert_fenced(data, before) do
    assert {:error, :oauth_refresh_in_progress} =
             rpc(data.second, :refresh, [data.tenant, data.id, 1])

    assert {:ok, held} = saved(data)
    assert Map.delete(held.secrets, "refresh_claim") == before.secrets
    deadline = DateTime.from_unix!(held.secrets["refresh_claim"]["deadline"])

    assert {:error, :oauth_reconnect_required} =
             rpc(data.second, :resolve, [data.tenant, data.id, deadline])
  end
end
