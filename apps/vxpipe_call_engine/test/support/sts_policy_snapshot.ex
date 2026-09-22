defmodule Vxpipe.CallEngine.TestSTSPolicySnapshot do
  @moduledoc false
  use GenServer

  def start_link(snapshot), do: GenServer.start_link(__MODULE__, snapshot)

  @impl true
  def init(snapshot), do: {:ok, snapshot}

  @impl true
  def handle_call(:snapshot, _from, snapshot), do: {:reply, snapshot, snapshot}

  def handle_call({:replace, snapshot}, _from, _previous), do: {:reply, :ok, snapshot}
end
