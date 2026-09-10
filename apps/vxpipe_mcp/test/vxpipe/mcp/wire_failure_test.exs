defmodule Vxpipe.MCP.WireFailureTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Vxpipe.MCP.{FaultClient, FaultServer}

  test "maps remote and unsupported errors without exposing server diagnostics" do
    for {fault, expected} <- [remote_error: :remote_error, unsupported: :remote_error] do
      log =
        capture_log(fn ->
          assert {:error, ^expected} = invoke(fault)
        end)

      refute log =~ "fixture-private-value"
      assert FaultServer.request_count("tools/call") == 1
    end
  end

  test "treats malformed and wrong-id responses as unknown after one submission" do
    for fault <- [:malformed, :wrong_id] do
      _log =
        capture_log(fn ->
          assert {:error, :outcome_unknown} = invoke(fault)
        end)

      assert FaultServer.request_count("tools/call") == 1
    end
  end

  test "assigns a request-scoped progress token to a tool call" do
    assert {:error, :remote_error} = invoke(:remote_error)
    request = FaultServer.take_request("tools/call")

    assert %{
             "params" => %{
               "_meta" => %{"progressToken" => progress_token}
             }
           } = request

    assert is_integer(progress_token) and progress_token > 0
  end

  defp invoke(fault) do
    server = start_supervised!({FaultServer, fault: fault, owner: self()})
    FaultClient.invoke(FaultServer.endpoint(server), fault)
  end
end
