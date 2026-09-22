defmodule Vxpipe.CallEngine.CallLoad.IngressObserver do
  @moduledoc "Counts optional ingress notifications without retaining frames."
  use GenServer

  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  def stats(observer, ingress), do: GenServer.call(observer, {:stats, ingress})

  @impl true
  def init(_options), do: {:ok, %{}}

  @impl true
  def handle_call({:stats, ingress}, _from, state), do: {:reply, Map.get(state, ingress), state}

  @impl true
  def handle_info({:vxpipe_media_ingress, ingress, {:delivered, _sequence}}, state),
    do: {:noreply, increment(state, ingress, :delivered)}

  def handle_info({:vxpipe_media_ingress, ingress, {:dropped, _reason, _sequence}}, state),
    do: {:noreply, increment(state, ingress, :dropped)}

  defp increment(state, ingress, key) do
    if map_size(state) >= 10 and not Map.has_key?(state, ingress),
      do: raise("ingress observer bound exceeded")

    Map.update(
      state,
      ingress,
      Map.put(%{delivered: 0, dropped: 0}, key, 1),
      &Map.update!(&1, key, fn count -> count + 1 end)
    )
  end
end
