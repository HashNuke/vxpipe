defmodule Vxpipe.CallEngine.STSBackgroundTool do
  @behaviour Vxpipe.CallEngine.Tool

  @impl true
  def definition, do: %{Vxpipe.CallEngine.STSLifecycleTool.definition() | name: "background"}

  @impl true
  defdelegate execute(arguments, context), to: Vxpipe.CallEngine.STSLifecycleTool
end
