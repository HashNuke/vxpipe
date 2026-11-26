defmodule Vxpipe.CallEngine.Tool.UpdateVariables do
  @moduledoc false

  @parameters %{
    "type" => "object",
    "properties" => %{
      "section_name" => %{"type" => "string"},
      "data" => %{"type" => "object", "additionalProperties" => true}
    },
    "required" => ["section_name", "data"],
    "additionalProperties" => false
  }

  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.{Context, Definition}

  @impl Vxpipe.CallEngine.Tool
  def definition do
    %Definition{
      name: "update_variables",
      description: "Recursively merge values into one writable Call Variables section.",
      parameters: @parameters
    }
  end

  @impl Vxpipe.CallEngine.Tool
  def execute(_arguments, %Context{}), do: {:error, :tool_failed}
end
