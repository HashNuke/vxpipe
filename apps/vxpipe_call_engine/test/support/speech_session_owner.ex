defmodule Vxpipe.CallEngine.SpeechSessionOwner do
  @moduledoc false
  use GenServer

  def start_link(observer), do: GenServer.start_link(__MODULE__, observer)
  def run(owner, operation), do: GenServer.call(owner, {:run, operation}, 5_000)

  @impl true
  def init(observer), do: {:ok, observer}

  @impl true
  def handle_call({:run, operation}, _from, observer),
    do: {:reply, operation.(:owner), observer}

  @impl true
  def handle_info(message, observer) do
    send(observer, {:speech_owner, self(), message})
    {:noreply, observer}
  end
end
