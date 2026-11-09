defmodule Vxpipe.CallEngine.STSToolResultReceiver do
  use GenServer

  def start_link(observer), do: GenServer.start_link(__MODULE__, observer)

  @impl true
  def init(observer), do: {:ok, observer}

  @impl true
  def handle_call({:send_tool_result, reference, result}, _from, observer) do
    send(observer, {:provider_tool_result, reference, result})
    {:reply, :ok, observer}
  end

  def handle_call(:hold, _from, observer) do
    send(observer, :sts_receiver_held)
    {:reply, :ok, observer}
  end

  @impl true
  def handle_info({:vxpipe_event, _event} = message, observer) do
    send(observer, message)
    {:noreply, observer}
  end
end
