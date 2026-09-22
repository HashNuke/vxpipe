defmodule Vxpipe.CallEngine.STSLifecycleTool do
  @behaviour Vxpipe.CallEngine.Tool

  alias Vxpipe.CallEngine.Tool.Definition

  @impl true
  def definition do
    %Definition{
      name: "lifecycle",
      description: "Controlled room invocation lifecycle fixture.",
      parameters: %{"type" => "object", "properties" => %{}, "additionalProperties" => false}
    }
  end

  @impl true
  def execute(%{}, context) do
    [{observer, nil}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {__MODULE__, context.room_id})

    send(observer, {:host_started, self(), context})
    await_result(observer)
  end

  defp await_result(observer) do
    receive do
      :probe ->
        send(observer, {:host_running, self()})
        await_result(observer)

      :finish ->
        {:ok, %{"retained" => true}}
    end
  end
end
