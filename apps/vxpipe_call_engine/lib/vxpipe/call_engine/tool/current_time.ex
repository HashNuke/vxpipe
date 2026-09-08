defmodule Vxpipe.CallEngine.Tool.CurrentTime do
  @moduledoc false

  use Jido.Action,
    name: "get_current_time",
    description: "Get the current date and time in UTC.",
    schema: []

  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.{Context, Definition}
  alias Vxpipe.CallEngine.Tool.Dispatcher

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
