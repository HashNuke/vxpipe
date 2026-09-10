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

  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.{Context, Definition}

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
end
