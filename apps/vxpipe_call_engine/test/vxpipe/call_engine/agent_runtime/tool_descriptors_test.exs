defmodule Vxpipe.CallEngine.AgentRuntime.ToolDescriptorsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.ToolDescriptor
  alias Vxpipe.CallEngine.AgentRuntime.ToolDescriptors
  alias Vxpipe.CallEngine.CallVariables.Binding
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.{TestAgentTool, TestSubmittedInlineTool}
  alias Vxpipe.CallEngine.Tool.InvocationBinding

  test "compiles resolved host bindings into ordered descriptors with private conversation policy" do
    bindings = %{
      "test_agent_tool" => host_binding("test_agent_tool", TestAgentTool, :blocking),
      "submitted_inline_tool" =>
        host_binding("submitted_inline_tool", TestSubmittedInlineTool, :non_blocking)
    }

    assert {:ok,
            [
              %ToolDescriptor{name: "submitted_inline_tool"} = non_blocking,
              %ToolDescriptor{name: "test_agent_tool"} = blocking
            ]} = ToolDescriptors.compile(bindings)

    assert non_blocking.description == "Wait for a test-controlled release."

    assert non_blocking.input_schema == %{
             "type" => "object",
             "properties" => %{"value" => %{"type" => "string"}},
             "required" => ["value"],
             "additionalProperties" => false
           }

    assert %InvocationBinding{
             name: "submitted_inline_tool",
             conversation_mode: :non_blocking,
             handler: {:host, TestSubmittedInlineTool}
           } = non_blocking.binding

    assert %InvocationBinding{conversation_mode: :blocking} = blocking.binding

    inspected = inspect(non_blocking)
    refute inspected =~ "InvocationBinding"
    refute inspected =~ "TestSubmittedInlineTool"
  end

  test "rejects a resolved binding stored under a different tool name" do
    binding = host_binding("test_agent_tool", TestAgentTool, :blocking)

    assert {:error, :invalid_tool_binding} =
             ToolDescriptors.compile(%{"different_name" => binding})
  end

  test "compiles permitted Call Variables tools as default-blocking private bindings" do
    variable_binding = variable_binding()

    assert {:ok, descriptors} = ToolDescriptors.compile(%{}, variable_binding)

    assert Enum.map(descriptors, & &1.name) == [
             "read_variables",
             "update_variable",
             "update_variables"
           ]

    assert Enum.all?(descriptors, fn descriptor ->
             match?(
               %InvocationBinding{
                 conversation_mode: :blocking,
                 handler: {:call_variables, ^variable_binding}
               },
               descriptor.binding
             )
           end)

    refute inspect(List.first(descriptors)) =~ "CallVariables.Binding"
  end

  defp host_binding(name, action, conversation_mode) do
    %ToolBinding{
      name: name,
      type: :host,
      conversation_mode: conversation_mode,
      action: action,
      remote: nil
    }
  end

  defp variable_binding do
    %Binding{
      server: self(),
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "incarnation-demo",
      participant_id: "participant-agent",
      activation_id: "activation-agent",
      read_sections: ["intake", "order"],
      write_sections: ["intake"]
    }
  end
end
