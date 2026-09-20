defmodule Vxpipe.CallEngine.SpeechSessionOwner do
  @moduledoc false
  use GenServer

  def start_link(observer), do: GenServer.start_link(__MODULE__, observer)
  def run(owner, operation), do: GenServer.call(owner, {:run, operation}, 5_000)
  def hold(owner), do: GenServer.call(owner, :hold, 5_000)
  def release(owner), do: GenServer.call(owner, :release, 5_000)

  @impl true
  def init(observer), do: {:ok, %{observer: observer, held?: false, held: []}}

  @impl true
  def handle_call({:run, operation}, _from, state),
    do: {:reply, operation.(:owner), state}

  def handle_call(:hold, _from, state), do: {:reply, :ok, %{state | held?: true}}

  def handle_call(:release, _from, state) do
    Enum.each(Enum.reverse(state.held), &send(state.observer, {:speech_owner, self(), &1}))
    {:reply, :ok, %{state | held?: false, held: []}}
  end

  @impl true
  def handle_info(message, %{held?: true} = state) do
    {:noreply, %{state | held: [message | state.held]}}
  end

  def handle_info(message, state) do
    send(state.observer, {:speech_owner, self(), message})
    {:noreply, state}
  end
end
