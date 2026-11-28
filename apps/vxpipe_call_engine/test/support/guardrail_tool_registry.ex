defmodule Vxpipe.CallEngine.TestGuardrailToolRegistry do
  @moduledoc false
  alias Vxpipe.AgentRuntime.{ToolDescriptor, ToolRegistry}

  def new do
    tools =
      for name <- ["lookup_order", "transfer"] do
        {:ok, descriptor} =
          ToolDescriptor.new(
            name: name,
            description: name,
            input_schema: %{"type" => "object"},
            binding: :fixture
          )

        descriptor
      end

    {:ok, registry} = ToolRegistry.new(tools)
    registry
  end
end
