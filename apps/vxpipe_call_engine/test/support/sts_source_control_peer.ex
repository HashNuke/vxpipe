defmodule Vxpipe.CallEngine.TestSTSSourceControlPeer do
  use GenServer

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def complete(peer, operation, result),
    do: GenServer.call(peer, {:complete, operation, result})

  @impl true
  def init(options), do: {:ok, %{observer: Keyword.fetch!(options, :observer), pending: %{}}}

  @impl true
  def handle_call({:vxpipe_sts_source_hold, scope}, from, state) do
    send(state.observer, {:sts_source_control_request, self(), :hold, scope})
    {:noreply, %{state | pending: Map.put(state.pending, :hold, from)}}
  end

  def handle_call({:vxpipe_sts_source_arm, scope}, from, state) do
    send(state.observer, {:sts_source_control_request, self(), :arm, scope})
    {:noreply, %{state | pending: Map.put(state.pending, :arm, from)}}
  end

  def handle_call({:complete, operation, result}, _from, state)
      when operation in [:hold, :arm] do
    case Map.pop(state.pending, operation) do
      {nil, _pending} ->
        {:reply, {:error, :no_request}, state}

      {request, pending} ->
        GenServer.reply(request, result)
        {:reply, :ok, %{state | pending: pending}}
    end
  end
end
