defmodule Vxpipe.MCP.WireLimitTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Vxpipe.MCP.{CumulativeSSEServer, FaultClient, FaultServer}

  @response_limit 1_024

  test "rejects compressed and incrementally oversized response bodies" do
    for fault <- [:compressed, :chunked_oversized, :sse_oversized] do
      server = start_supervised!({FaultServer, fault: fault, owner: self()})

      _log =
        capture_log(fn ->
          assert {:error, :outcome_unknown} =
                   FaultClient.invoke(FaultServer.endpoint(server), fault,
                     max_response_bytes: @response_limit,
                     max_stream_buffer_bytes: @response_limit
                   )
        end)

      assert FaultServer.request_count("tools/call") == 1
    end
  end

  test "retains an unknown outcome after timeout or disconnect" do
    for fault <- [:slow, :disconnect] do
      server = start_supervised!({FaultServer, fault: fault, owner: self()})

      _log =
        capture_log(fn ->
          assert {:error, :outcome_unknown} =
                   FaultClient.invoke(FaultServer.endpoint(server), fault, deadline_ms: 100)
        end)

      assert FaultServer.request_count("tools/call") == 1
    end
  end

  test "keeps the response budget across complete progress events and reconnection" do
    server = start_supervised!({CumulativeSSEServer, owner: self()})

    task_supervisor = start_supervised!(Task.Supervisor)

    task =
      Task.Supervisor.async_nolink(task_supervisor, fn ->
        FaultClient.invoke(CumulativeSSEServer.endpoint(server), :cumulative_sse_oversized,
          deadline_ms: 5_000,
          max_response_bytes: @response_limit,
          max_stream_buffer_bytes: @response_limit,
          use_sse: true
        )
      end)

    assert_receive {:cumulative_sse_initial_stream, initial_stream}, 1_000
    assert_receive {:cumulative_sse_request, "tools/call", request}, 1_000
    assert_receive {:cumulative_sse_post_stream, post_stream}, 1_000

    progress_token = get_in(request, ["params", "_meta", "progressToken"])
    assert is_integer(progress_token)

    send(post_stream, :close_stream)
    assert_receive {:cumulative_sse_resumed_stream, resumed_stream, ["event-2"]}, 2_000
    send(resumed_stream, {:emit_progress, progress_token})

    assert {:ok, {:error, :outcome_unknown}} = Task.yield(task, 1_000)
    send(initial_stream, :close_stream)
    send(resumed_stream, :close_stream)
    refute_receive {:cumulative_sse_request, "tools/call", _request}, 100
  end
end
