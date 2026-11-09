defmodule Vxpipe.Console.Integration.NativeSavedMCPTest do
  use Vxpipe.Console.Test.SavedMCPRuntimeCase, async: false

  alias Vxpipe.{CallEngine, Calls}
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Tree
  alias Vxpipe.Persistence.MCP.ConnectionStore
  alias Vxpipe.Providers.MorseCode.STSSession

  setup c do
    configure_admission(c.options)
    settings = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

    Application.put_env(
      :vxpipe_call_engine,
      CallEngine.Application,
      Keyword.put(settings, :speech_to_speech, providers: %{STSSession => [enabled: true]})
    )

    :ok
  end

  for change <- [:disconnect, :replacement] do
    @tag hold_mcp_invocation: true
    test "native #{change} allows one submitted outcome and denies the next invocation", c do
      active = start_native(c)
      capability = capability(active)
      sessions = Tree.remote_mcp_sessions(capability)
      monitor = Process.monitor(sessions)

      assert :ok = request_lookup(capability, "customer-42")
      assert_call("customer-42")
      assert_receive {:remote_mcp_wire_invocation_held, handler, reference, _request}, 5_000
      on_exit(fn -> send(handler, {:cancel_remote_mcp_wire_invocation, reference}) end)

      change_connection(c, unquote(change))
      send(handler, {:release_remote_mcp_wire_invocation, reference})
      assert_receive {:remote_mcp_wire_invocation_released, ^reference}, 5_000
      assert native_result(c, active) == found("customer-42")

      assert :ok = request_lookup(capability, "customer-43")
      assert %{"error" => _reason} = native_result(c, active)
      refute_received {:remote_mcp_wire_request, "tools/call", _, _}
      refute_received {:remote_mcp_wire_invocation_held, _, _, _}

      assert {:ok, current} = Calls.fetch_call(c.tenant, active.call.id, c.options)
      assert current.state == :running
      assert current.incarnation_id == active.call.incarnation_id
      close_admitted_call(c, active.call)
      assert_receive {:DOWN, ^monitor, :process, ^sessions, _reason}, 5_000
      refute_received {:remote_mcp_wire_request, "tools/call", _, _}
      refute_received {:remote_mcp_wire_request, "tools/list", _, _}
      refute_received {:remote_mcp_wire_invocation_held, _, _, _}
      refute_received {:remote_mcp_wire_invocation_timeout, _}
    end

    test "native prepared admission rejects saved #{change} before opening an MCP session", c do
      prepared = prepare_web_call(c, native_source(c))
      change_connection(c, unquote(change))
      failed_admission(c, prepared)
    end
  end

  test "native stale catalog pins fail admission and fresh arguments use the saved schema", c do
    prepared = prepare_web_call(c, native_source(c))

    changed =
      put_in(tool("lookup_customer"), ["inputSchema", "properties", "customer_id", "enum"], [
        "customer-43"
      ])

    assert {:ok, _} =
             ConnectionStore.refresh_catalog(
               c.context,
               c.tenant,
               c.connection.id,
               1,
               Map.take(c.connection, [:refreshed_at, :refresh_scheduled_at]),
               %{catalog: [changed, tool("unselected")], server_name: "Records"}
             )

    failed_admission(c, prepared)
    active = admit_web_call(c, prepare_existing_web_call(c, prepared.create_path))
    capability = capability(active)

    assert :ok = request_lookup(capability, "customer-42")
    assert %{"error" => _reason} = native_result(c, active)
    refute_received {:remote_mcp_wire_request, "tools/call", _, _}

    assert :ok = request_lookup(capability, "customer-43")
    assert_call("customer-43")
    assert native_result(c, active) == found("customer-43")
    close_admitted_call(c, active.call)
    refute_received {:remote_mcp_wire_request, "tools/list", _, _}
    refute_received {:remote_mcp_wire_request, "tools/call", _, _}
  end

  defp start_native(c), do: admit_web_call(c, prepare_web_call(c, native_source(c)))

  defp native_source(c) do
    source(c.connection.id)
    |> Map.put(:tool_visibility, "full")
    |> put_in([:participants, "assistant", :capabilities], %{
      speech_to_speech: %{provider: "morse", model: "morse"}
    })
  end

  defp capability(active) do
    agent = Map.fetch!(active.call.plan.participants, "assistant")

    capability =
      CallEngine.RoomCapabilitySupervisor.whereis_speech_to_speech(
        active.call.incarnation_id,
        agent.participant_id
      )

    assert is_pid(capability)
    capability
  end

  defp request_lookup(capability, customer) do
    SpeechToSpeech.push_text(
      capability,
      "TOOL records__lookup_customer " <> JSON.encode!(%{"customer_id" => customer})
    )
  end

  defp assert_call(customer) do
    assert_receive {:remote_mcp_wire_request, "tools/call", _,
                    %{
                      "params" => %{
                        "name" => "lookup_customer",
                        "arguments" => %{"customer_id" => ^customer}
                      }
                    }},
                   5_000
  end

  defp native_result(c, active) do
    message = await_web(c, active.peer, active.channel, "llm-function-call-stopped")
    assert message["data"]["function_name"] == "records__lookup_customer"
    refute message["data"]["cancelled"]
    [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {c.tenant, active.call.room_id})
    _ = :sys.get_state(authority)
    message["data"]["result"]
  end

  defp found(customer),
    do: %{"content" => [%{"type" => "text", "text" => "found #{customer}"}]}

  defp change_connection(c, :disconnect), do: assert(disconnect(c).status == 200)

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

    assert replacement.generation == 2
  end
end
