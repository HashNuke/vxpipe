defmodule Vxpipe.CallEngine.TestAgentTool do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.{Context, Definition}

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
end
