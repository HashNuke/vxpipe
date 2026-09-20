defmodule Vxpipe.CallEngine.SpeechTopologyUsage do
  @moduledoc false
  use GenServer

  @maximum_facts 2

  def start_link(_options), do: GenServer.start_link(__MODULE__, %{})

  def publish(usage, fact), do: GenServer.call(usage, {:publish, fact})
  def take(usage, request), do: GenServer.call(usage, {:take, request})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:publish, %{request_ref: request} = fact}, _from, state) do
    cond do
      Map.has_key?(state, request) ->
        {:reply, :ok, state}

      map_size(state) >= @maximum_facts ->
        {:reply, {:error, :usage_overflow}, state}

      true ->
        {:reply, :ok, Map.put(state, request, fact)}
    end
  end

  def handle_call({:take, request}, _from, state) do
    case Map.pop(state, request) do
      {nil, _state} -> {:reply, {:error, :unknown_request}, state}
      {fact, state} -> {:reply, {:ok, fact}, state}
    end
  end
end
