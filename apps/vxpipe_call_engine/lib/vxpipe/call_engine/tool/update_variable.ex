defmodule Vxpipe.CallEngine.Tool.UpdateVariable do
  @moduledoc false

  @parameters %{
    "type" => "object",
    "properties" => %{
      "section_name" => %{"type" => "string"},
      "variable_name" => %{"type" => "string"},
      "value" => %{},
      "expected_revision" => %{"type" => "integer", "minimum" => 0}
    },
    "required" => ["section_name", "variable_name", "value", "expected_revision"],
    "additionalProperties" => false
  }

  use Jido.Action,
    name: "update_variable",
    description: "Set one literal variable in a writable Call Variables section.",
    schema: @parameters

  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.{Context, Definition, Dispatcher}

  @impl Vxpipe.CallEngine.Tool
  def definition do
    %Definition{
      name: "update_variable",
      description: "Set one literal variable in a writable Call Variables section.",
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
