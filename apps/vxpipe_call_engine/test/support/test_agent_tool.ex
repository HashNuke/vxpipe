defmodule Vxpipe.CallEngine.TestAgentTool do
  @moduledoc false

  use Jido.Action,
    name: "test_agent_tool",
    description: "Return a value through the Vxpipe host-action boundary.",
    schema: [value: [type: :string, required: true]]

  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.{Context, Definition, Dispatcher}

  @impl Vxpipe.CallEngine.Tool
  def definition do
    %Definition{
      name: "test_agent_tool",
      description: "Return a value through the Vxpipe host-action boundary.",
      parameters: %{
        "type" => "object",
        "properties" => %{"value" => %{"type" => "string"}},
        "required" => ["value"],
        "additionalProperties" => false
      }
    }
  end

  @impl Vxpipe.CallEngine.Tool
  def execute(%{"value" => value}, %Context{}) when is_binary(value),
    do: {:ok, %{"value" => value}}

  def execute(%{value: value}, %Context{}) when is_binary(value),
    do: {:ok, %{"value" => value}}

  def execute(_arguments, %Context{}), do: {:error, :invalid_arguments}

  @impl Jido.Action
  def run(arguments, context) when is_map(arguments) and is_map(context) do
    with dispatcher when not is_nil(dispatcher) <- Map.get(context, :vxpipe_tool_dispatcher),
         %Context{} = tool_context <- Map.get(context, :vxpipe_tool_context) do
      Dispatcher.execute(dispatcher, name(), arguments, tool_context)
    else
      _invalid -> {:error, :tool_failed}
    end
  end
end
