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

  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.{Context, Definition}

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
end
