defmodule Vxpipe.CallEngine.TestReadinessAdapter do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Readiness.Adapter
  alias Vxpipe.CallEngine.Readiness.Resource

  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  @impl Vxpipe.CallEngine.Readiness.Adapter
  def readiness(server), do: GenServer.call(server, :readiness, 5_000)
  def resource(server), do: GenServer.call(server, :resource)
  def reply(server, status), do: GenServer.call(server, {:reply, status})

  @impl true
  def init(options) do
    resource =
      Resource.new(:room_service, :room, __MODULE__, :configured,
        binding: Keyword.fetch!(options, :id)
      )

    {:ok, %{resource: resource, observer: Keyword.fetch!(options, :observer), waiting: []}}
  end

  @impl true
  def handle_call(:resource, _from, state), do: {:reply, state.resource, state}

  def handle_call(:readiness, from, state) do
    send(state.observer, {:readiness_requested, self()})
    send(state.observer, {:readiness_probe_caller, self(), elem(from, 0)})
    {:noreply, %{state | waiting: [from | state.waiting]}}
  end

  def handle_call({:reply, status}, _from, state) do
    Enum.each(state.waiting, &GenServer.reply(&1, {:ok, state.resource, status}))
    {:reply, :ok, %{state | waiting: []}}
  end
end
