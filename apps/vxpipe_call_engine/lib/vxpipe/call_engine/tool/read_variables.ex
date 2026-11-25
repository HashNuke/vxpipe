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
    "additionalProperties" => false
  }

  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.{Context, Definition}

  @impl Vxpipe.CallEngine.Tool
  def definition do
    %Definition{
      name: "read_variables",
      description:
        "Read permitted Call Variables and writable form schemas. Omit sections to read all permitted sections.",
      parameters: @parameters
    }
  end

  @impl Vxpipe.CallEngine.Tool
  def execute(_arguments, %Context{}), do: {:error, :tool_failed}
end
