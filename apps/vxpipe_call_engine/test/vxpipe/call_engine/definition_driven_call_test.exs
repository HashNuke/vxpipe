defmodule Vxpipe.CallEngine.DefinitionDrivenCallTest do
  use ExUnit.Case, async: false

  import Jido.AI.Test

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    AgentActivationSupervisor,
    CallDefinition,
    CallInvocation,
    DefinitionCompiler
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}

  alias Vxpipe.CallEngine.Event.{
    AgentTurnCompleted,
    ParticipantTurnCompleted,
    ParticipantTurnStarted,
    TextOutput,
    ToolCallCompleted,
    ToolCallStarted
  }

  alias Vxpipe.CallEngine.Tool.CurrentTime

  test "starts only entry participants and routes an attached caller through Jido" do
    room_id = unique_id("room")
    plan = compile_plan(room_id)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)
    unused = Map.fetch!(plan.participants, "unused-agent")

    script =
      expect_react do
        user("What time is it?")
        call("get_current_time", %{}, id: "tool-clock")
        answer("The host action completed.")
      end

    assert {:ok, room} =
             CallEngine.start_call(plan,
               agent_request_options: Jido.AI.Test.react_opts(script)
             )

    assert room.room_id == room_id

    assert participant_registered?(room_id, caller.participant_id)
    assert participant_registered?(room_id, receiver.participant_id)
    refute participant_registered?(room_id, unused.participant_id)
    assert AgentActivationSupervisor.whereis_child(unused.activation_id, :agent_server) == nil

    assert {:ok, attach} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: "conn-definition-test",
               deadline: future_deadline()
             )

    assert {:ok, _attachment} = CallEngine.attach_connection(attach)

    assert {:ok, command} =
             SendText.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: attach.connection_id,
               correlation_id: "turn-definition-test",
               content: "What time is it?",
               deadline: future_deadline()
             )

    assert :ok = CallEngine.send_text(command)

    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 1}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 2}}

    assert_receive {:vxpipe_event,
                    %ToolCallStarted{
                      sequence: 3,
                      participant_id: agent_participant_id,
                      tool_call_id: "tool-clock",
                      name: "get_current_time",
                      arguments: %{}
                    }}

    assert agent_participant_id == receiver.participant_id

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      sequence: 4,
                      tool_call_id: "tool-clock",
                      result: %{"timezone" => "UTC"}
                    }}

    assert_receive {:vxpipe_event, %TextOutput{sequence: 5, text: "The host action completed."}}

    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 6}}
  end

  test "routes the next room turn through a restarted agent activation" do
    room_id = unique_id("room")
    plan = compile_plan(room_id)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    script =
      expect_react do
        user("Are you ready?")
        answer("Ready after restart.")
      end

    assert {:ok, room} =
             CallEngine.start_call(plan,
               agent_request_options: Jido.AI.Test.react_opts(script)
             )

    assert [{activation_supervisor, _value}] =
             Registry.lookup(
               Vxpipe.CallEngine.RoomRegistry,
               {:agent_activation, receiver.activation_id, :supervisor}
             )

    first = AgentActivationSupervisor.children(activation_supervisor)
    monitors = monitor_children(first)
    Process.exit(Map.fetch!(first, :agent_server), :kill)
    assert_children_stopped(monitors)
    _ = :sys.get_state(activation_supervisor)

    second = AgentActivationSupervisor.children(activation_supervisor)

    assert Enum.all?(second, fn {role, pid} ->
             is_pid(pid) and pid != Map.fetch!(first, role)
           end)

    attach_caller(plan, room, caller, "conn-restarted")
    command = send_command(plan, room, caller, "conn-restarted", "Are you ready?")

    assert :ok = CallEngine.send_text(command)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 1}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 2}}
    assert_receive {:vxpipe_event, %TextOutput{sequence: 3, text: "Ready after restart."}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 4}}
  end

  defp compile_plan(room_id) do
    assert {:ok, definition} =
             CallDefinition.new(definition_input(), resource_id: "definition-test", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "definition-test", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-test",
               actor_id: "actor-test",
               call_id: unique_id("call"),
               room_id: room_id
             )

    registries = %{
      capability_profiles: %{
        "test-model" => %{
          kind: :model_inference,
          provider: :req_llm,
          options: %{model: "test:scripted"}
        }
      },
      host_tools: %{"get_current_time" => CurrentTime}
    }

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries)
    plan
  end

  defp definition_input do
    %{
      schema_version: "20260906.02",
      entry_caller: "caller",
      entry_receiver: "receiver",
      defaults: %{capabilities: %{}},
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "receiver" => %{
          type: "agent",
          prompt: "Use the available host action.",
          first_message: %{mode: "wait_for_input"},
          capabilities: %{model_inference: "test-model"},
          tools: %{
            "get_current_time" => %{type: "host", tool: "get_current_time"}
          },
          transfers: []
        },
        "unused-agent" => %{
          type: "agent",
          prompt: "This participant must not be started.",
          first_message: %{mode: "wait_for_input"},
          capabilities: %{model_inference: "test-model"},
          tools: %{},
          transfers: []
        }
      },
      limits: %{max_duration_ms: 60_000}
    }
  end

  defp participant_registered?(room_id, participant_id) do
    match?(
      [{_pid, _value}],
      Registry.lookup(
        Vxpipe.CallEngine.RoomRegistry,
        {:participant, "tenant-test", room_id, participant_id}
      )
    )
  end

  defp attach_caller(plan, room, caller, connection_id) do
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

    assert {:ok, _attachment} = CallEngine.attach_connection(command)
  end

  defp send_command(plan, room, caller, connection_id, content) do
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

    command
  end

  defp monitor_children(children) do
    Map.new(children, fn {role, pid} -> {role, {pid, Process.monitor(pid)}} end)
  end

  defp assert_children_stopped(monitors) do
    Enum.each(monitors, fn {_role, {pid, monitor}} ->
      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 1_000
    end)
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
