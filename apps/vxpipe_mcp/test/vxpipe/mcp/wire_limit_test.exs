defmodule Vxpipe.MCP.WireLimitTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Vxpipe.MCP.{FaultClient, FaultServer}

  @response_limit 1_024

  test "rejects compressed and incrementally oversized response bodies" do
    faults = [
      compressed: "compressed_response",
      chunked_oversized: "response_too_large",
      sse_oversized: "response_too_large"
    ]

    for {fault, expected_cause} <- faults do
      server = start_supervised!({FaultServer, fault: fault, owner: self()})

      log =
        capture_log(fn ->
          assert {:error, :outcome_unknown} =
                   FaultClient.invoke(FaultServer.endpoint(server), fault,
                     max_response_bytes: @response_limit,
                     max_stream_buffer_bytes: @response_limit
                   )
        end)

      refute log =~ "FunctionClauseError"
      assert log =~ expected_cause
      assert FaultServer.request_count("tools/call") == 1
    end
  end

  test "retains an unknown outcome after timeout or disconnect" do
    for fault <- [:slow, :disconnect] do
      server = start_supervised!({FaultServer, fault: fault, owner: self()})

      log =
        capture_log(fn ->
          assert {:error, :outcome_unknown} =
                   FaultClient.invoke(FaultServer.endpoint(server), fault, deadline_ms: 100)
        end)

      refute log =~ "FunctionClauseError"
      assert FaultServer.request_count("tools/call") == 1
    end
  end
end
