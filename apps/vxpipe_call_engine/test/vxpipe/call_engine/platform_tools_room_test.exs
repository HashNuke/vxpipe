defmodule Vxpipe.CallEngine.PlatformToolsRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}
  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    DefinitionCompiler,
    TestAgentRuntimeModelProvider,
    TestCollectingArchiveWriter
  }

  alias Vxpipe.CallEngine.Archive.Fact
  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}
  alias Vxpipe.CallEngine.Event.{ToolCallCompleted, ToolCallStarted}
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.Tool.{CurrentTime, Hangup}

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:fixture, {TestAgentRuntimeModelProvider, [owner: self()]})

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :agent_runtime, agent_runtime)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  test "resolves platform tools and lets permitted hangup end the room" do
    plan = compile_plan()
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    assert %ToolBinding{
             name: "current_time",
             type: :platform,
             conversation_mode: :blocking,
             action: CurrentTime
           } = receiver.tools["current_time"]

    assert %ToolBinding{
             name: "end_call",
             type: :platform,
             conversation_mode: :blocking,
             action: Hangup
           } = receiver.tools["end_call"]

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    connection_id = "conn-platform-hangup"

    archive = [
      enabled: true,
      writer: {TestCollectingArchiveWriter, self()},
      maximum_pending_facts: 32,
      retry_delay_ms: 5,
      drain_timeout_ms: 1_000
    ]

    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan, archive: archive)
    assert {:ok, attach} = attach(plan, room, caller, connection_id)

    assert :ok = send_text(plan, room, caller, connection_id, "Please end the call.")
    assert_receive {:test_agent_runtime_stream, provider, request}
    assert Enum.map(request.tools, & &1.name) == ["current_time", "end_call"]

    assert {:ok, call} = ToolCall.new(id: "hangup-1", name: "end_call", arguments: %{})
    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_event, %ToolCallStarted{tool_call_id: "hangup-1"}}

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "hangup-1",
                      result: %{"status" => "ending"}
                    }}

    assert_receive {:DOWN, monitor, :process, _pid, _reason}
    assert monitor == attach.room_monitor

    assert_receive {:test_archive_fact, %Fact{kind: :archive_stream_closed} = closure}
    assert closure.payload["source_reason"] == "shutdown"
  end

  defp compile_plan do
    input = %{
      schema_version: CallDefinition.schema_version(),
      entry_caller: "caller",
      entry_receiver: "receiver",
      defaults: %{capabilities: %{}},
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: %{}
        },
        "receiver" => %{
          type: "agent",
          prompt: "Use the available platform tools.",
          first_message: %{mode: "wait_for_input"},
          capabilities: %{model_inference: %{provider: "fixture", model: "test:scripted"}},
          tools: %{
            "current_time" => %{type: "platform", tool: "get_current_time"},
            "end_call" => %{type: "platform", tool: "hangup"}
          },
          transfers: []
        }
      },
      limits: %{max_duration_ms: 60_000}
    }

    assert {:ok, definition} =
             CallDefinition.new(input, resource_id: "platform-tools-definition", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "platform-tools-definition", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-test",
               actor_id: "actor-test",
               call_id: unique_id("call"),
               room_id: unique_id("room")
             )

    registries = %{
      host_tools: %{}
    }

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries)
    plan
  end

  defp attach(plan, room, caller, connection_id) do
    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: connection_id,
               deadline: future_deadline()
             )

    with {:ok, attachment} <- CallEngine.attach_connection(command) do
      Vxpipe.CallEngine.TestCallStartup.await_ready(attachment)
      {:ok, attachment}
    end
  end

  defp send_text(plan, room, caller, connection_id, content) do
    assert {:ok, command} =
             SendText.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: connection_id,
               correlation_id: unique_id("turn"),
               content: content,
               deadline: future_deadline()
             )

    CallEngine.send_text(command)
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)
  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
