defmodule Vxpipe.CallEngine.TestVariableProjectionDispatcher do
  @moduledoc false

  use GenServer

  def start_link(options) do
    GenServer.start_link(__MODULE__, Keyword.fetch!(options, :projection))
  end

  def replace(server, projection), do: GenServer.call(server, {:replace, projection})

  @impl true
  def init(projection), do: {:ok, projection}

  @impl true
  def handle_call(:variable_projection, _from, projection),
    do: {:reply, {:ok, projection}, projection}

  def handle_call({:replace, projection}, _from, _current), do: {:reply, :ok, projection}
end
