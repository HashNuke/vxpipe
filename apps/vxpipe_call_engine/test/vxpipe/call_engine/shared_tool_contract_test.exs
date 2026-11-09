defmodule Vxpipe.CallEngine.SharedToolContractTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Event.{ToolCallCompleted, ToolCallFailed, ToolCallStarted}
  alias Vxpipe.CallEngine.ToolContractRoom, as: Room

  @moduletag :shared_tool_contract

  setup context do
    Room.configure!(Map.get(context, :tool_limits, []))
    :ok
  end

  for path <- [:llm, "morse", "morse-duplex"], mode <- ["blocking", "non_blocking"] do
    test "#{path} #{mode} receptionist looks up MCP, updates variables, continues and hangs up" do
      context = Room.start!(unquote(path), unquote(mode))
      registry_monitor = Process.monitor(context.registry)
      session_monitor = Process.monitor(context.mcp_session)
      authority_monitor = Process.monitor(context.authority)
      assert [:ok] = Room.invoke(context, "customer_lookup", %{"customer_id" => "42"})
      assert_receive {:test_remote_mcp_invocation_started, worker}, 1_000
      assert_receive {:vxpipe_event, %ToolCallStarted{name: "customer_lookup"} = started}, 1_000

      control_start = System.monotonic_time(:microsecond)
      assert %CallEngine.Room.Snapshot{} = GenServer.call(context.authority, :snapshot, 250)
      control_us = System.monotonic_time(:microsecond) - control_start

      if unquote(mode) == "blocking" do
        Room.input(context, "EARLY")
        refute_receive {:vxpipe_event, %CallEngine.Event.TextOutput{text: "REPLY EARLY"}}, 50
        refute_received {:vxpipe_event, %CallEngine.Event.TextOutput{text: "RECEIVED EARLY"}}
      else
        Room.converse!(context, "EARLY")
      end

      release_start = System.monotonic_time(:microsecond)
      send(worker, :release_test_remote_mcp)
      id = started.tool_call_id

      assert_receive {:vxpipe_event,
                      %ToolCallCompleted{name: "customer_lookup", tool_call_id: ^id} = result},
                     1_000

      assert result.result == context.result
      Room.consumed!(context)
      completion_us = System.monotonic_time(:microsecond) - release_start
      assert [_one_remote_invocation] = Agent.get(context.client, & &1.invocations)

      assert [:ok] =
               Room.invoke(context, "update_variables", %{
                 "section_name" => "intake",
                 "data" => %{"appointment" => "FOUND"},
                 "expected_revision" => 0
               })

      assert_receive {:vxpipe_event,
                      %ToolCallCompleted{
                        name: "update_variables",
                        result: %{"revision" => 1, "value" => %{"appointment" => "FOUND"}}
                      }},
                     1_000

      Room.consumed!(context)
      Room.converse!(context)

      if unquote(mode) == "blocking" do
        refute_received {:vxpipe_event, %CallEngine.Event.TextOutput{text: "REPLY EARLY"}}
        refute_received {:vxpipe_event, %CallEngine.Event.TextOutput{text: "RECEIVED EARLY"}}
      end

      assert [:ok] = Room.invoke(context, "end_call", %{})
      assert_receive {:vxpipe_event, %ToolCallCompleted{name: "end_call"}}, 1_000
      assert_receive {:DOWN, ^registry_monitor, :process, _, _}, 1_000
      assert_receive {:DOWN, ^session_monitor, :process, _, _}, 1_000
      assert_receive {:DOWN, ^authority_monitor, :process, _, _}, 1_000

      IO.puts(
        "Tool contract #{unquote(path)}/#{unquote(mode)}: startup_us=#{context.startup_us}, pending_control_us=#{control_us}, release_to_consumed_us=#{completion_us}; owned registry/session DOWN"
      )
    end

    for {label, response, reason} <- [
          {:failed, {:error, :remote_error}, :tool_failed},
          {:unknown, {:error, :outcome_unknown}, :unknown}
        ] do
      test "#{path} #{mode} retains a #{label} MCP outcome without retrying work" do
        context = Room.start!(unquote(path), unquote(mode), response: unquote(response))
        monitor = Process.monitor(context.mcp_session)
        assert [:ok] = Room.invoke(context, "customer_lookup", %{"customer_id" => "42"})
        assert_receive {:test_remote_mcp_invocation_started, worker}, 1_000
        assert_receive {:vxpipe_event, %ToolCallStarted{name: "customer_lookup"}}, 1_000
        send(worker, :release_test_remote_mcp)

        assert_receive {:vxpipe_event,
                        %ToolCallFailed{name: "customer_lookup", reason: unquote(reason)}},
                       1_000

        Room.consumed!(context)
        assert [_single_attempt] = Agent.get(context.client, & &1.invocations)
        assert [:ok] = Room.invoke(context, "end_call", %{})
        assert_receive {:vxpipe_event, %ToolCallCompleted{name: "end_call"}}, 1_000
        assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
        Room.await_closed!(context)
      end
    end

    test "#{path} #{mode} rejects an unselected operation without executing MCP work" do
      context = Room.start!(unquote(path), unquote(mode))
      assert [:ok] = Room.invoke(context, "private_operation", %{})
      Room.rejected!(context, :unauthorized)
      Room.consumed!(context)
      assert Agent.get(context.client, & &1.invocations) == []
      assert [:ok] = Room.invoke(context, "end_call", %{})
      assert_receive {:vxpipe_event, %ToolCallCompleted{name: "end_call"}}, 1_000
      Room.await_closed!(context)
    end
  end

  for path <- [:llm, "morse", "morse-duplex"] do
    @tag :duplicate_contract
    test "#{path} a repeated invocation identity cannot repeat pending MCP work" do
      context = Room.start!(unquote(path), "non_blocking")
      replay = Room.replayable!(context, "customer_lookup", %{"customer_id" => "42"})
      assert_receive {:test_remote_mcp_invocation_started, worker}, 1_000
      assert_receive {:vxpipe_event, %ToolCallStarted{name: "customer_lookup"} = accepted}, 1_000
      Room.replay!(context, replay)
      refute_received {:test_remote_mcp_invocation_started, _}
      refute_received {:vxpipe_event, %ToolCallStarted{name: "customer_lookup"}}
      send(worker, :release_test_remote_mcp)
      id = accepted.tool_call_id
      assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: ^id}}, 1_000
      Room.consumed!(context)
      assert [_one_attempt] = Agent.get(context.client, & &1.invocations)
      refute_received {:vxpipe_event, %ToolCallCompleted{tool_call_id: ^id}}
      Room.close!(context)
    end

    @tag tool_limits: [maximum_tool_invocations: 1]
    test "#{path} partial admission preserves accepted work and recovers capacity" do
      context = Room.start!(unquote(path), "non_blocking")
      assert [:ok] = Room.invoke(context, "customer_lookup", %{"customer_id" => "first"})
      assert_receive {:test_remote_mcp_invocation_started, worker}, 1_000
      assert_receive {:vxpipe_event, %ToolCallStarted{name: "customer_lookup"} = accepted}, 1_000
      assert [:ok] = Room.invoke(context, "customer_lookup", %{"customer_id" => "second"})
      Room.rejected!(context, :saturated)
      refute_received {:test_remote_mcp_invocation_started, _}
      refute_received {:vxpipe_event, %ToolCallStarted{name: "customer_lookup"}}
      send(worker, :release_test_remote_mcp)
      id = accepted.tool_call_id
      assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: ^id}}, 1_000
      Room.consumed!(context)
      assert [_single_attempt] = Agent.get(context.client, & &1.invocations)
      assert [:ok] = Room.invoke(context, "current_time", %{})
      assert_receive {:vxpipe_event, %ToolCallCompleted{name: "current_time"}}, 1_000
      Room.consumed!(context)
      Room.close!(context)
    end
  end

  @tag tool_limits: [maximum_tool_invocations: 1]
  test "one multi-tool LLM response retains its admitted subset after saturation" do
    context = Room.start!(:llm, "non_blocking")

    assert [:ok] =
             Room.invoke_many(context, [
               {"customer_lookup", %{"customer_id" => "first"}},
               {"customer_lookup", %{"customer_id" => "second"}}
             ])

    assert_receive {:test_remote_mcp_invocation_started, worker}, 1_000
    assert_receive {:vxpipe_event, %ToolCallStarted{name: "customer_lookup"} = accepted}, 1_000
    Room.rejected!(context, :saturated)
    refute_received {:test_remote_mcp_invocation_started, _}
    refute_received {:vxpipe_event, %ToolCallStarted{name: "customer_lookup"}}
    send(worker, :release_test_remote_mcp)
    id = accepted.tool_call_id
    assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: ^id}}, 1_000
    Room.consumed!(context)
    assert [_one_attempt] = Agent.get(context.client, & &1.invocations)
    assert [:ok] = Room.invoke(context, "current_time", %{})
    assert_receive {:vxpipe_event, %ToolCallCompleted{name: "current_time"}}, 1_000
    Room.consumed!(context)
    Room.close!(context)
  end
end
