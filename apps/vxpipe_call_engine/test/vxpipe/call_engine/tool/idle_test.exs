defmodule Vxpipe.CallEngine.Tool.IdleTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallSpec.ToolSelection
  alias Vxpipe.CallEngine.{Error, ResolvedCallPlan}

  alias Vxpipe.CallEngine.Tool.{
    Context,
    CurrentTime,
    Idle,
    InvocationBinding,
    InvocationConfig,
    InvocationSubmission,
    PlatformCatalog
  }

  alias Vxpipe.CallEngine.Tool.Idle.Request

  test "idle exposes one bounded integer argument with no additional properties" do
    assert {:ok, Idle} = PlatformCatalog.fetch("idle")
    definition = Idle.definition()
    assert definition.name == "idle"

    assert definition.parameters == %{
             "type" => "object",
             "properties" => %{
               "duration_seconds" => %{"type" => "integer", "minimum" => 1, "maximum" => 300}
             },
             "required" => ["duration_seconds"],
             "additionalProperties" => false
           }
  end

  test "requests preserve native invocation context and reject coercion or extra arguments" do
    context = context()

    for seconds <- [1, 10, 300] do
      assert {:ok, request} = Request.new(%{"duration_seconds" => seconds}, context)
      assert request.context == context
      assert request.duration_seconds == seconds
    end

    for arguments <- [
          %{},
          %{"duration_seconds" => 0},
          %{"duration_seconds" => -1},
          %{"duration_seconds" => 301},
          %{"duration_seconds" => 10.0},
          %{"duration_seconds" => "10"},
          %{"duration_seconds" => nil},
          %{"duration_seconds" => 10, "other" => true},
          %{duration_seconds: 10},
          nil,
          []
        ] do
      assert {:error, :invalid_arguments} = Request.new(arguments, context)
      assert {:error, :invalid_arguments} = Idle.execute(arguments, context)
    end

    assert {:error, :invalid_arguments} =
             Request.new(%{"duration_seconds" => 10}, %{context | tool_call_id: nil})

    assert {:error, :unavailable} = Idle.execute(%{"duration_seconds" => 10}, context)
  end

  test "platform idle and aliases remain non-blocking while other tools retain their defaults" do
    path = ["participants", "agent", "tools", "pause"]
    assert {:ok, selection} = ToolSelection.new("pause", %{type: "platform", tool: "idle"}, path)
    assert selection.conversation_mode == :non_blocking

    assert {:ok, explicit} =
             ToolSelection.new(
               "pause",
               %{type: "platform", tool: "idle", conversation_mode: "non_blocking"},
               path
             )

    assert explicit.conversation_mode == :non_blocking

    assert {:error, %Error{details: details}} =
             ToolSelection.new(
               "pause",
               %{type: "platform", tool: "idle", conversation_mode: "blocking"},
               path
             )

    assert details["path"] == path ++ ["conversation_mode"]

    assert {:ok, other} =
             ToolSelection.new(
               "get_current_time",
               %{type: "platform", tool: "get_current_time"},
               path
             )

    assert other.conversation_mode == :blocking
    assert {:ok, host} = ToolSelection.new("idle", %{type: "host", tool: "idle"}, path)
    assert host.conversation_mode == :blocking
  end

  test "resolved and direct invocation bindings cannot make idle block human input" do
    resolved = %ResolvedCallPlan.ToolBinding{
      name: "pause",
      type: :platform,
      conversation_mode: :non_blocking,
      action: Idle,
      remote: nil
    }

    assert {:ok, binding} = InvocationBinding.from_resolved(resolved)
    assert InvocationBinding.valid?(binding)
    refute InvocationBinding.valid?(%{binding | conversation_mode: :blocking})

    assert {:error, :invalid_binding} =
             InvocationBinding.from_resolved(%{resolved | conversation_mode: :blocking})
  end

  test "only native idle receives its quiet interval and bounded acknowledgment budget" do
    idle = %InvocationBinding{
      name: "pause",
      conversation_mode: :non_blocking,
      handler: {:platform, Idle}
    }

    assert {:ok, submission} =
             InvocationSubmission.new(idle, %{"duration_seconds" => 10}, context(), "idle-budget")

    assert InvocationConfig.for_invocation(submission, 1_000) == 45_000
    assert InvocationConfig.for_invocation(submission, 60_000) == 60_000

    assert {:ok, maximum} =
             InvocationSubmission.new(
               idle,
               %{"duration_seconds" => 300},
               context(),
               "idle-budget"
             )

    assert InvocationConfig.for_invocation(maximum, 1_000) == 335_000

    assert {:ok, invalid} =
             InvocationSubmission.new(
               idle,
               %{"duration_seconds" => "300"},
               context(),
               "idle-budget"
             )

    assert InvocationConfig.for_invocation(invalid, 1_000) == 1_000

    regular = %InvocationBinding{
      name: "get_current_time",
      conversation_mode: :blocking,
      handler: {:platform, CurrentTime}
    }

    assert {:ok, normal} =
             InvocationSubmission.new(
               regular,
               %{"duration_seconds" => 300},
               context(),
               "idle-budget"
             )

    assert InvocationConfig.for_invocation(normal, 1_000) == 1_000
  end

  test "publication rejects native idle for legacy or speech-to-speech profiles" do
    alias Vxpipe.CallEngine.{
      AgentProtocol,
      CallInvocation,
      CallSpec,
      CallSpecCompiler,
      TestTurnCall
    }

    input = TestTurnCall.call_spec(tools: %{"idle" => %{type: "platform", tool: "idle"}})
    assert {:ok, spec} = CallSpec.new(input, resource_id: "idle-profile", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: "idle-profile", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant",
               actor_id: "actor"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
    assert {:ok, modern} = AgentProtocol.capture()
    assert {:ok, legacy} = AgentProtocol.capture(:legacy)
    assert {:ok, _} = AgentProtocol.pin(plan, modern)

    for protocol <- [nil, legacy] do
      assert {:error, %Error{code: :unsupported_agent_protocol}} =
               AgentProtocol.pin(plan, protocol)
    end

    agent = Map.fetch!(plan.participants, "receiver")

    capabilities = %{
      agent.capabilities
      | model_inference: nil,
        speech_to_speech: agent.capabilities.model_inference
    }

    sts = %{
      plan
      | participants:
          Map.put(plan.participants, "receiver", %{agent | capabilities: capabilities})
    }

    assert {:error, %Error{code: :unsupported_agent_protocol}} = AgentProtocol.pin(sts, modern)
  end

  defp context do
    %Context{
      tenant_id: "absent-idle-tenant",
      room_id: "absent-idle-room",
      incarnation_id: "incarnation",
      agent_participant_id: "agent",
      source_participant_id: "human",
      connection_id: "human-connection",
      command_id: "origin-command",
      correlation_id: "origin-turn",
      agent_request_id: "request",
      tool_call_id: "idle-budget"
    }
  end
end
