defmodule Vxpipe.CallEngine.Tool.UpdateVariable do
  @moduledoc false

  @parameters %{
    "type" => "object",
    "properties" => %{
      "section_name" => %{"type" => "string"},
      "variable_name" => %{"type" => "string"},
      "variable_value" => %{}
    },
    "required" => ["section_name", "variable_name", "variable_value"],
    "additionalProperties" => false
  }

  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.{Context, Definition}

  @impl Vxpipe.CallEngine.Tool
  def definition do
    %Definition{
      name: "update_variable",
      description:
        "Set one field in a writable section. Pass its literal JSON value directly as variable_value.",
      parameters: @parameters
    }
  end

  @impl Vxpipe.CallEngine.Tool
  def execute(_arguments, %Context{}), do: {:error, :tool_failed}
end
