defmodule Vxpipe.Console.SavedMCPTelephonyTest do
  use Vxpipe.Console.Test.SavedMCPRuntimeCase, async: false

  alias Vxpipe.Calls
  alias Vxpipe.Console.Test.SavedMCPTelephonyCase, as: Phone

  setup c, do: Phone.configure(c)

  for {direction, legacy, label} <- [
        {:incoming, false, "managed incoming"},
        {:outgoing, false, "managed outgoing"},
        {:incoming, true, "legacy incoming"}
      ] do
    @tag direction: direction, legacy: legacy
    test "saved MCP tools execute through #{label} phone admission", c do
      published = Phone.publish(c, c.direction)
      active = apply(Phone, c.direction, [c, published])
      {provider, request} = Phone.model_input(c, active, 0, "Find customer-42.")
      assert Enum.map(request.tools, & &1.name) == ["records__lookup_customer"]
      reply_tool(provider, "phone-first", "customer-42")

      assert_receive {:remote_mcp_wire_request, "tools/call", _,
                      %{
                        "params" => %{
                          "name" => "lookup_customer",
                          "arguments" => %{"customer_id" => "customer-42"}
                        }
                      }},
                     5_000

      {completion, result} = Phone.tool_result(c, active, "phone-first")

      assert %{
               "status" => "completed",
               "result" => %{"content" => [%{"text" => "found customer-42"}]}
             } =
               tool_outcome(result, "phone-first")

      Phone.finish_speech(c, active, completion, "I found customer-42.")

      assert disconnect(c) |> json_response(200) |> get_in(["connection", "status"]) == "revoked"
      {next, _} = Phone.model_input(c, active, 1, "Find customer-43.")
      reply_tool(next, "phone-revoked", "customer-43")
      {failed, result} = Phone.tool_result(c, active, "phone-revoked")
      assert tool_outcome(result, "phone-revoked") == %{"status" => "failed"}
      refute_received {:remote_mcp_wire_request, "tools/call", _, _}
      Phone.finish_speech(c, active, failed, "The records connection is unavailable.")

      assert {:ok, current} = Calls.fetch_call(c.tenant, active.call.id, c.options)
      assert current.state == :running
      assert current.incarnation_id == active.call.incarnation_id
      Phone.close(c, active)
      refute_received {:remote_mcp_wire_request, "tools/call", _, _}
    end
  end
end
