defmodule Vxpipe.CallEngine.TestBlockingTool do
  @moduledoc false

  use Jido.Action,
    name: "wait_for_test",
    description: "Wait until a test releases this tool.",
    schema: []

  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.{Context, Definition, Dispatcher}

  @impl Vxpipe.CallEngine.Tool
  def definition do
    %Definition{
      name: "wait_for_test",
      description: "Wait until a test releases this tool.",
      parameters: %{"type" => "object", "properties" => %{}},
      execution: :background
    }
  end

  @impl Vxpipe.CallEngine.Tool
  def execute(%{}, %Context{}) do
    observer = Application.fetch_env!(:vxpipe_call_engine, :blocking_tool_observer)
    send(observer, {:test_blocking_tool_started, self()})

    receive do
      :release_test_tool -> {:ok, %{"released" => true}}
    end
  end

  @impl Jido.Action
  def run(arguments, context) when is_map(arguments) and is_map(context) do
    with dispatcher when not is_nil(dispatcher) <- Map.get(context, :vxpipe_tool_dispatcher),
         %Context{} = tool_context <- Map.get(context, :vxpipe_tool_context) do
      Dispatcher.submit(dispatcher, name(), arguments, tool_context)
    else
      _invalid -> {:error, :tool_failed}
    end
  end
end
