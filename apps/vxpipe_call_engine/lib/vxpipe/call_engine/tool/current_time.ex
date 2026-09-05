defmodule Vxpipe.CallEngine.Tool.CurrentTime do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.{Context, Definition}

  @impl true
  def definition do
    %Definition{
      name: "get_current_time",
      description: "Get the current date and time in UTC.",
      parameters: %{
        "type" => "object",
        "properties" => %{},
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def execute(arguments, %Context{}) when map_size(arguments) == 0 do
    {:ok,
     %{
       "timezone" => "UTC",
       "iso8601" => DateTime.utc_now(:second) |> DateTime.to_iso8601()
     }}
  end

  def execute(_arguments, %Context{}), do: {:error, :invalid_arguments}
end
