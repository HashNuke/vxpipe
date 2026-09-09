defmodule Vxpipe.CallEngine.Tool.ReadVariables do
  @moduledoc false

  @parameters %{
    "type" => "object",
    "properties" => %{
      "sections" => %{
        "type" => "array",
        "items" => %{"type" => "string"},
        "minItems" => 1,
        "maxItems" => 32
      }
    },
    "required" => ["sections"],
    "additionalProperties" => false
  }

  use Jido.Action,
    name: "read_variables",
    description: "Read selected Call Variables sections that this agent may access.",
    schema: @parameters

  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.{Context, Definition, Dispatcher}

  @impl Vxpipe.CallEngine.Tool
  def definition do
    %Definition{
      name: "read_variables",
      description: "Read selected Call Variables sections that this agent may access.",
      parameters: @parameters
    }
  end

  @impl Vxpipe.CallEngine.Tool
  def execute(_arguments, %Context{}), do: {:error, :tool_failed}

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
