defmodule Vxpipe.Console.Integration.SavedMCPTransferTest do
  use Vxpipe.Console.Test.SavedMCPRuntimeCase, async: false

  alias Vxpipe.{CallEngine, Calls}
  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}
  alias Vxpipe.Persistence.MCP.ConnectionStore

  test "a delayed destination executes its saved MCP through the original admitted peer", c do
    configure_admission(c.options)
    active = source_room(c)
    transfer(c, active)
    transfer_stopped(c, active, %{"destination" => "records", "status" => "completed"})
    assert_absent(c, active, "assistant")
    assert_present(c, active, "records")
    assert_receive {:test_agent_runtime_stream, _retired_source, pending}, 5_000
    assert_pending_transfer(c, pending)
    lookup(c, active, "destination-lookup")
    assert_same_call(c, active)
    close_admitted_call(c, active.call)
    refute_received {:remote_mcp_wire_request, "tools/call", _, _}
  end

  for reuse <- [:cold, :warm], change <- [:revocation, :replacement] do
    @reuse reuse
    @change change
    @tag hold_mcp_stream: reuse == :warm
    test "#{@change} rejects a delayed destination with a #{@reuse} client and preserves the source",
         c do
      configure_admission(c.options)

      sibling =
        if @reuse == :warm do
          sibling = admit_web_call(c, prepare_web_call(c, source(c.connection.id)))
          lookup(c, sibling, "sibling-lookup")
          sibling
        end

      active = source_room(c)

      stream =
        if sibling do
          assert_receive {:remote_mcp_wire_request, "initialize",
                          "Bearer synthetic-saved-runtime-token", _},
                         5_000

          assert_receive {:remote_mcp_wire_request, "notifications/initialized",
                          "Bearer synthetic-saved-runtime-token", _},
                         5_000

          assert_receive {:remote_mcp_wire_stream, "Bearer synthetic-saved-runtime-token"}, 5_000
          assert_receive {:remote_mcp_wire_stream_open, handler, reference}, 5_000
          on_exit(fn -> send(handler, {:release_remote_mcp_wire_stream, reference}) end)
          {handler, reference}
        end

      refute_received {:remote_mcp_wire_request, _, _, _}
      change_connection(c, @change)
      transfer(c, active)
      transfer_stopped(c, active, %{"error" => "tool_failed"})
      assert_present(c, active, "assistant")
      assert_absent(c, active, "records")

      assert_receive {:test_agent_runtime_stream, acknowledgement, pending}, 5_000
      assert_pending_transfer(c, pending)
      reply_text(acknowledgement, "Checking the transfer.")

      assert await_web(c, active.peer, active.channel, "bot-output")["data"]["text"] ==
               "Checking the transfer."

      await_web(c, active.peer, active.channel, "bot-stopped-speaking")

      assert_receive {:test_agent_runtime_stream, completion, failed}, 5_000
      assert_private_absent(c, failed)
      assert tool_outcome(failed, "transfer-records", "transfer") == %{"status" => "failed"}
      finish_text(c, active, completion, "The records agent is unavailable.")

      {provider, request} = model_input(c, active, "Are you still there?")
      assert hd(request.messages).content == "Route callers safely."

      assert Enum.any?(
               request.messages,
               &(&1.role == :user and &1.content == "Are you still there?")
             )

      finish_text(c, active, provider, "Yes, I can still help.")
      assert_same_call(c, active)
      close_admitted_call(c, active.call)
      if sibling, do: close_admitted_call(c, sibling.call)

      if stream do
        {handler, reference} = stream
        send(handler, {:release_remote_mcp_wire_stream, reference})
        assert_receive {:remote_mcp_wire_stream_released, ^reference}, 5_000
        refute_received {:remote_mcp_wire_stream_timeout, ^reference}
      end

      refute_received {:remote_mcp_wire_request, _, _, _}
      refute_received {:remote_mcp_wire_stream, _}
    end
  end

  defp change_connection(c, :revocation), do: assert(disconnect(c).status == 200)

  defp change_connection(c, :replacement) do
    assert {:ok, saved} = ConnectionStore.resolve(c.context, c.tenant, c.connection.id)

    assert {:ok, replacement} =
             ConnectionStore.replace(
               c.context,
               c.tenant,
               c.connection.id,
               1,
               c.attributes,
               saved.secrets
             )

    assert replacement.id == c.connection.id
    assert replacement.generation == 2
  end

  defp source_room(c) do
    original = source(c.connection.id)
    destination = Map.fetch!(original.participants, "assistant")

    reception = %{
      destination
      | tools: %{},
        prompt: "Route callers safely.",
        transfers: ["records"]
    }

    participants =
      original.participants |> Map.put("assistant", reception) |> Map.put("records", destination)

    source = original |> Map.put(:participants, participants) |> Map.put(:tool_visibility, "full")
    active = admit_web_call(c, prepare_web_call(c, source))
    {provider, request} = model_input(c, active, "Hello reception.")
    assert hd(request.messages).content == "Route callers safely."
    assert Enum.map(request.tools, & &1.name) == ["transfer"]
    finish_text(c, active, provider, "How can I help?")
    assert_present(c, active, "assistant")
    assert_absent(c, active, "records")
    active
  end

  defp transfer(c, active) do
    {provider, request} = model_input(c, active, "Please transfer me to records.")
    assert hd(request.messages).content == "Route callers safely."

    assert {:ok, tool} =
             ToolCall.new(
               id: "transfer-records",
               name: "transfer",
               arguments: %{"destination" => "records"}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [tool])
    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  defp transfer_stopped(c, active, result) do
    message = await_web(c, active.peer, active.channel, "llm-function-call-stopped")
    assert message["data"]["tool_call_id"] == "transfer-records"
    assert message["data"]["function_name"] == "transfer"
    refute message["data"]["cancelled"]
    assert message["data"]["result"] == result
  end

  defp assert_pending_transfer(c, request) do
    assert_private_absent(c, request)
    assert hd(request.messages).content == "Route callers safely."
    assert request.tools == []

    assert Enum.any?(request.messages, fn message ->
             message.role == :tool and message.tool_call_id == "transfer-records" and
               JSON.decode!(message.content) == %{
                 "invocation_id" => "transfer-records",
                 "status" => "running"
               }
           end)
  end

  defp lookup(c, active, id) do
    {provider, request} = model_input(c, active, "Find customer-42.")
    assert hd(request.messages).content == "Use the records tool."
    assert Enum.map(request.tools, & &1.name) == ["records__lookup_customer"]
    reply_tool(provider, id, "customer-42")

    assert_receive {:remote_mcp_wire_request, "tools/call",
                    "Bearer synthetic-saved-runtime-token",
                    %{
                      "params" => %{
                        "name" => "lookup_customer",
                        "arguments" => %{"customer_id" => "customer-42"}
                      }
                    }},
                   5_000

    {completion, result} = await_tool_result(c, id, active.peer, active.channel)
    assert_private_absent(c, result)

    assert tool_outcome(result, id) == %{
             "status" => "completed",
             "result" => %{"content" => [%{"type" => "text", "text" => "found customer-42"}]}
           }

    finish_text(c, active, completion, "Found customer-42.")
  end

  defp assert_present(c, active, key) do
    participant = Map.fetch!(active.call.plan.participants, key)

    assert {:ok, snapshot} =
             CallEngine.participant_snapshot(
               c.tenant,
               active.call.room_id,
               participant.participant_id
             )

    assert snapshot.participant_id == participant.participant_id
  end

  defp assert_absent(c, active, key) do
    participant = Map.fetch!(active.call.plan.participants, key)

    assert {:error, %Vxpipe.CallEngine.Error{code: :participant_not_found}} =
             CallEngine.participant_snapshot(
               c.tenant,
               active.call.room_id,
               participant.participant_id
             )
  end

  defp assert_same_call(c, active) do
    assert {:ok, current} = Calls.fetch_call(c.tenant, active.call.id, c.options)
    assert current.state == :running
    assert current.incarnation_id == active.call.incarnation_id
  end
end
