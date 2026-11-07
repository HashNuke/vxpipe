defmodule Vxpipe.Console.Integration.SavedMCPInflightTest do
  use Vxpipe.Console.Test.SavedMCPRuntimeCase, async: false

  alias Vxpipe.Calls

  @moduletag hold_mcp_stream: true, hold_mcp_invocation: true

  test "disconnect permits one already-submitted result but prevents retry and later submissions",
       c do
    configure_admission(c.options)
    active = admit_web_call(c, prepare_web_call(c, source(c.connection.id)))

    assert_receive {:remote_mcp_wire_request, "initialize",
                    "Bearer synthetic-saved-runtime-token", _},
                   5_000

    assert_receive {:remote_mcp_wire_request, "notifications/initialized",
                    "Bearer synthetic-saved-runtime-token", _},
                   5_000

    assert_receive {:remote_mcp_wire_stream, "Bearer synthetic-saved-runtime-token"}, 5_000
    assert_receive {:remote_mcp_wire_stream_open, stream, stream_ref}, 5_000
    on_exit(fn -> send(stream, {:release_remote_mcp_wire_stream, stream_ref}) end)

    {provider, request} = model_input(c, active, "Find customer-42.")
    assert Enum.map(request.tools, & &1.name) == ["records__lookup_customer"]
    reply_tool(provider, "submitted-before-disconnect", "customer-42")

    assert_receive {:remote_mcp_wire_request, "tools/call",
                    "Bearer synthetic-saved-runtime-token",
                    %{
                      "id" => request_id,
                      "params" => %{
                        "name" => "lookup_customer",
                        "arguments" => %{"customer_id" => "customer-42"}
                      }
                    }},
                   5_000

    assert_receive {:remote_mcp_wire_invocation_held, handler, reference, ^request_id}, 5_000
    on_exit(fn -> send(handler, {:cancel_remote_mcp_wire_invocation, reference}) end)
    assert disconnect(c).status == 200
    send(handler, {:release_remote_mcp_wire_invocation, reference})
    assert_receive {:remote_mcp_wire_invocation_released, ^reference}, 5_000

    {completion, result} =
      await_tool_result(c, "submitted-before-disconnect", active.peer, active.channel)

    assert_private_absent(c, result)

    assert tool_outcome(result, "submitted-before-disconnect") == %{
             "status" => "completed",
             "result" => %{"content" => [%{"type" => "text", "text" => "found customer-42"}]}
           }

    finish_text(c, active, completion, "The submitted lookup found customer-42.")
    refute_received {:remote_mcp_wire_request, _, _, _}
    refute_received {:remote_mcp_wire_stream, _}

    {provider, _request} = model_input(c, active, "Now find customer-43.")
    reply_tool(provider, "after-disconnect", "customer-43")
    {completion, result} = await_tool_result(c, "after-disconnect", active.peer, active.channel)
    assert_private_absent(c, result)
    assert tool_outcome(result, "after-disconnect") == %{"status" => "failed"}
    finish_text(c, active, completion, "Records are disconnected.")

    assert {:ok, current} = Calls.fetch_call(c.tenant, active.call.id, c.options)
    assert current.state == :running
    assert current.incarnation_id == active.call.incarnation_id
    close_admitted_call(c, active.call)
    send(stream, {:release_remote_mcp_wire_stream, stream_ref})
    assert_receive {:remote_mcp_wire_stream_released, ^stream_ref}, 5_000
    refute_received {:remote_mcp_wire_invocation_timeout, _}
    refute_received {:remote_mcp_wire_stream_timeout, _}
    refute_received {:remote_mcp_wire_invocation_held, _, _, _}
    refute_received {:remote_mcp_wire_stream_open, _, _}
    refute_received {:remote_mcp_wire_stream, _}
    refute_received {:remote_mcp_wire_request, _, _, _}
  end
end
