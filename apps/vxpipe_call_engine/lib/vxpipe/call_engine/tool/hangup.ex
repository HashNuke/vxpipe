defmodule Vxpipe.CallEngine.Tool.Hangup do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.{Context, Definition, PlatformResult}

  @impl true
  def definition do
    %Definition{
      name: "hangup",
      description: "End the current call immediately.",
      parameters: %{
        "type" => "object",
        "properties" => %{},
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def execute(arguments, %Context{}) when map_size(arguments) == 0 do
    {:ok, %PlatformResult{effect: :hangup, result: %{"status" => "ending"}}}
  end

  def execute(_arguments, %Context{}), do: {:error, :invalid_arguments}
end
