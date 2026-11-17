defmodule Vxpipe.CallEngine.TestScopedInterruptReply do
  use GenServer
  def start_link(replies), do: GenServer.start_link(__MODULE__, replies)
  def init(replies), do: {:ok, replies}

  def handle_call({:interrupt, requests}, _from, replies) do
    if MapSet.new(requests) == MapSet.new(Enum.map(replies, &elem(&1, 0))) do
      {:reply, {:ok, replies}, replies}
    else
      {:reply, {:error, :unavailable}, replies}
    end
  end
end
