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

  test "keeps aliases for one session executor exact and independently attributed" do
    first =
      descriptor(
        "lookup_order",
        %{handler: Vxpipe.AgentRuntime.TestExecutor, binding_id: "orders-primary"},
        "Look up an order",
        "order_id"
      )

    second =
      descriptor(
        "find_purchase",
        %{handler: Vxpipe.AgentRuntime.TestExecutor, binding_id: "orders-secondary"},
        "Find a purchase",
        "purchase_id"
      )

    assert {:ok, registry} = ToolRegistry.new([first, second])

    assert [
             %ModelTool{
               name: "lookup_order",
               description: "Look up an order",
               input_schema: first_schema
             },
             %ModelTool{
               name: "find_purchase",
               description: "Find a purchase",
               input_schema: second_schema
             }
           ] = ToolRegistry.model_tools(registry)

    assert first_schema == first.input_schema
    assert second_schema == second.input_schema

    assert {:ok, ^first} =
             ToolRegistry.resolve(registry, "lookup_order", %{"order_id" => "order-1"})

    assert {:ok, ^second} =
             ToolRegistry.resolve(registry, "find_purchase", %{"purchase_id" => "purchase-1"})

    assert first.binding.handler == second.binding.handler
    refute first.binding.binding_id == second.binding.binding_id
  end

  defp descriptor(name, binding, description \\ "Look up an order", field \\ "order_id") do
    {:ok, descriptor} =
      ToolDescriptor.new(
        name: name,
        description: description,
        input_schema: %{
          "type" => "object",
          "properties" => %{field => %{"type" => "string"}},
          "required" => [field],
          "additionalProperties" => false
        },
        binding: binding
      )

    descriptor
  end
end
