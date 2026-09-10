defmodule Vxpipe.AgentRuntime.ToolRegistryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{ModelTool, ToolDescriptor, ToolRegistry}

  test "projects only model-visible fields and resolves valid arguments to the private binding" do
    descriptor = descriptor("lookup_order", %{credential: "private-secret"})

    assert {:ok, registry} = ToolRegistry.new([descriptor])
    assert [%ModelTool{name: "lookup_order"} = model_tool] = ToolRegistry.model_tools(registry)
    assert model_tool.description == "Look up an order"
    assert model_tool.input_schema == descriptor.input_schema
    refute Map.has_key?(Map.from_struct(model_tool), :binding)
    refute inspect(registry) =~ "private-secret"

    assert {:ok, ^descriptor} =
             ToolRegistry.resolve(registry, "lookup_order", %{"order_id" => "order_1"})

    assert {:error, :invalid_arguments} = ToolRegistry.resolve(registry, "lookup_order", %{})
    assert {:error, :unknown_tool} = ToolRegistry.resolve(registry, "other", %{})
  end

  test "rejects duplicate local names" do
    assert {:error, :duplicate_tool} =
             ToolRegistry.new([
               descriptor("lookup_order", :first),
               descriptor("lookup_order", :second)
             ])
  end

  defp descriptor(name, binding) do
    {:ok, descriptor} =
      ToolDescriptor.new(
        name: name,
        description: "Look up an order",
        input_schema: %{
          "type" => "object",
          "properties" => %{"order_id" => %{"type" => "string"}},
          "required" => ["order_id"],
          "additionalProperties" => false
        },
        binding: binding
      )

    descriptor
  end
end
