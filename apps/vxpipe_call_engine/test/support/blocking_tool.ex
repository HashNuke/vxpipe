defmodule Vxpipe.CallEngine.TestBlockingTool do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.{Context, Definition}

  def definition do
    %Definition{
      name: "wait_for_test",
      description: "Wait until a test releases this tool.",
      parameters: %{"type" => "object", "properties" => %{}},
      execution: :background
    }
  end

  def execute(%{}, %Context{}) do
    observer = Application.fetch_env!(:vxpipe_call_engine, :blocking_tool_observer)
    send(observer, {:test_blocking_tool_started, self()})

    receive do
      :release_test_tool -> {:ok, %{"released" => true}}
    end
  end
end
