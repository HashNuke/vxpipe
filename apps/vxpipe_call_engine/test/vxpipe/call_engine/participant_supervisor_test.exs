defmodule Vxpipe.CallEngine.ParticipantSupervisorTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.AgentActivationSupervisor
  alias Vxpipe.CallEngine.Command.JoinParticipant
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.RoomParticipantSupervisor
  alias Vxpipe.CallEngine.{TestAgentRuntimeModelProvider, TestAgentTool}

  test "an agent participant owns its configured activation subtree" do
    incarnation_id = unique_id("rinc")
    activation_id = unique_id("activation")
    participant_id = unique_id("agent")

    _room_participants =
      start_supervised!({RoomParticipantSupervisor, incarnation_id: incarnation_id})

    assert {:ok, command} =
             JoinParticipant.new(
               tenant_id: "tenant-test",
               actor_id: "actor-test",
               room_id: unique_id("room"),
               participant_id: participant_id,
               role: :agent,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, participant_supervisor, participant} =
             RoomParticipantSupervisor.start_participant(
               incarnation_id,
               command,
               agent_activation: activation_options(activation_id, participant_id)
             )

    assert participant.participant_id == participant_id

    assert [{participant_authority, _value}] =
             Registry.lookup(
               Vxpipe.CallEngine.RoomRegistry,
               {:participant, "tenant-test", command.room_id, participant_id}
             )

    assert [{activation_supervisor, _value}] =
             Registry.lookup(
               Vxpipe.CallEngine.RoomRegistry,
               {:agent_activation, activation_id, :supervisor}
             )

    assert is_pid(AgentActivationSupervisor.whereis_child(activation_id, :session))

    authority_monitor = Process.monitor(participant_authority)
    activation_monitor = Process.monitor(activation_supervisor)

    assert :ok =
             RoomParticipantSupervisor.stop_participant(
               incarnation_id,
               participant_supervisor
             )

    assert_receive {:DOWN, ^authority_monitor, :process, ^participant_authority, :shutdown}
    assert_receive {:DOWN, ^activation_monitor, :process, ^activation_supervisor, :shutdown}

    assert {:ok, human_command} =
             JoinParticipant.new(
               tenant_id: "tenant-test",
               actor_id: "actor-test",
               room_id: command.room_id,
               participant_id: unique_id("human"),
               role: :human,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, _human_supervisor, _human} =
             RoomParticipantSupervisor.start_participant(incarnation_id, human_command)
  end

  test "an exhausted agent activation ends only its participant subtree" do
    incarnation_id = unique_id("rinc")
    activation_id = unique_id("activation")
    participant_id = unique_id("agent")

    _room_participants =
      start_supervised!({RoomParticipantSupervisor, incarnation_id: incarnation_id})

    command = join_command(unique_id("room"), participant_id, :agent)

    assert {:ok, participant_supervisor, _participant} =
             RoomParticipantSupervisor.start_participant(
               incarnation_id,
               command,
               agent_activation: activation_options(activation_id, participant_id)
             )

    assert [{activation_supervisor, _value}] =
             Registry.lookup(
               Vxpipe.CallEngine.RoomRegistry,
               {:agent_activation, activation_id, :supervisor}
             )

    first = AgentActivationSupervisor.children(activation_supervisor)
    first_monitors = monitor_children(first)
    Process.exit(Map.fetch!(first, :session), :kill)
    assert_children_stopped(first_monitors)

    _ = :sys.get_state(activation_supervisor)

    second = AgentActivationSupervisor.children(activation_supervisor)

    assert Enum.all?(second, fn {role, pid} ->
             is_pid(pid) and pid != Map.fetch!(first, role)
           end)

    participant_monitor = Process.monitor(participant_supervisor)
    Process.exit(Map.fetch!(second, :session), :kill)

    assert_receive {:DOWN, ^participant_monitor, :process, ^participant_supervisor, _reason},
                   1_000

    human_command = join_command(command.room_id, unique_id("human"), :human)

    assert {:ok, _human_supervisor, _human} =
             RoomParticipantSupervisor.start_participant(incarnation_id, human_command)
  end

  defp activation_options(activation_id, participant_id) do
    [
      runtime: :agent_runtime,
      activation_id: activation_id,
      agent_participant_id: participant_id,
      owner: self(),
      system_prompt: "Use the selected action.",
      tools: %{
        "test_agent_tool" => %ToolBinding{
          name: "test_agent_tool",
          type: :host,
          conversation_mode: :blocking,
          action: TestAgentTool,
          remote: nil
        }
      },
      variable_binding: nil,
      model_provider: TestAgentRuntimeModelProvider,
      model: %{model: "test:scripted", owner: self()},
      provider: :test,
      background_tool_timeout_ms: 1_000,
      maximum_background_tools: 2,
      maximum_completed_requests: 4,
      maximum_output_bytes: 65_536,
      maximum_pending_requests: 2,
      maximum_tool_result_bytes: 4_096,
      request_timeout_ms: 1_000
    ]
  end

  defp join_command(room_id, participant_id, role) do
    assert {:ok, command} =
             JoinParticipant.new(
               tenant_id: "tenant-test",
               actor_id: "actor-test",
               room_id: room_id,
               participant_id: participant_id,
               role: role,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    command
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp monitor_children(children) do
    Map.new(children, fn {role, pid} -> {role, {pid, Process.monitor(pid)}} end)
  end

  defp assert_children_stopped(monitors) do
    Enum.each(monitors, fn {_role, {pid, monitor}} ->
      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 1_000
    end)
  end
end
