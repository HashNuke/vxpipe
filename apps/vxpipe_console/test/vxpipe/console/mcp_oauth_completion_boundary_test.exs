defmodule Vxpipe.Console.MCPOAuthCompletionBoundaryTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Console.MCPOAuthCompletion
  alias Vxpipe.MCP.{OAuthCallback, PreflightRunner}

  test "capacity rejection happens before DNS or code redemption" do
    owner = self()
    opts = options(owner, nil, runner(limit: 0))
    assert {:error, :mcp_connection_busy} = complete(opts)
    refute_received :dns
    refute_received :exchange
    refute_received :check
  end

  for stage <- [:dns, :exchange, :check] do
    test "whole-operation deadline stops held #{stage} work" do
      stage = unquote(stage)
      owner = self()
      opts = options(owner, stage, runner(timeout: 1000))
      start_supervised!({Task, fn -> send(owner, {:result, complete(opts)}) end})
      assert_receive {:held, ^stage, worker}, 1000
      monitor = Process.monitor(worker)
      on_exit(fn -> Process.exit(worker, :kill) end)
      assert_receive {:result, {:error, :mcp_connection_timed_out}}, 2000
      assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1000
    end

    test "caller death stops held #{stage} work" do
      stage = unquote(stage)
      owner = self()
      opts = options(owner, stage, runner(timeout: 5000))
      caller = start_supervised!({Task, fn -> complete(opts) end})
      caller_monitor = Process.monitor(caller)
      assert_receive {:held, ^stage, worker}, 1000
      monitor = Process.monitor(worker)
      on_exit(fn -> Process.exit(worker, :kill) end)
      stop_supervised!(Task)
      assert_receive {:DOWN, ^caller_monitor, :process, ^caller, _}, 1000
      assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1000
    end
  end

  defp runner(settings) do
    tasks = start_supervised!({Task.Supervisor, []})

    start_supervised!(
      {PreflightRunner, [name: nil, task_supervisor: tasks, interval: 0] ++ settings}
    )
  end

  defp options(owner, held, runner) do
    [
      completion_runner: runner,
      dns_resolver: fn _, _ ->
        maybe_hold(owner, held, :dns)
        {:ok, [{93, 184, 216, 34}]}
      end,
      request_fun: fn _, _, _, _ ->
        maybe_hold(owner, held, :exchange)

        {:ok,
         {{~c"HTTP/1.1", 200, ~c"OK"}, [],
          JSON.encode!(%{
            "access_token" => "fixture-access",
            "token_type" => "Bearer",
            "expires_in" => 300
          })}}
      end,
      connection_check: fn _, _ ->
        maybe_hold(owner, held, :check)
        {:ok, %{server_name: "Tools", catalog: []}}
      end
    ]
  end

  defp maybe_hold(owner, stage, stage) do
    send(owner, {:held, stage, self()})

    receive do
      :release -> :ok
    end
  end

  defp maybe_hold(owner, _held, stage), do: send(owner, stage)

  defp complete(options) do
    callback = %OAuthCallback{
      state: String.duplicate("s", 43),
      code: "code",
      issuer: "https://auth.test"
    }

    attempt = %Vxpipe.Calls.ResolvedMCPOAuthAttempt{
      attempt: %{
        connection_id: "connection",
        generation: 1,
        issuer: "https://auth.test",
        resource: "https://mcp.test/mcp",
        redirect_uri: "https://console.test/oauth/mcp/callback"
      },
      secrets: %{
        "code_verifier" => String.duplicate("v", 43),
        "client_id" => "client",
        "auth_method" => "none",
        "token_endpoint" => "https://auth.test/token",
        "issuer_response_required" => true
      }
    }

    MCPOAuthCompletion.complete(options, "tenant", callback, attempt)
  end
end
