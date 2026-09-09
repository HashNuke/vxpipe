defmodule Vxpipe.CallEngine.TelemetrySampler do
  @moduledoc """
  Periodically samples call-engine and VM gauges outside live room callbacks.
  """

  use GenServer

  alias Vxpipe.CallEngine.Telemetry

  @call_timeout 5_000

  def start_link(options) do
    genserver_options =
      case Keyword.get(options, :name, __MODULE__) do
        nil -> []
        name -> [name: name]
      end

    GenServer.start_link(__MODULE__, options, genserver_options)
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.get(options, :name, __MODULE__)},
      start: {__MODULE__, :start_link, [options]}
    }
  end

  @doc "Samples immediately and returns the emitted measurements."
  @spec sample(GenServer.server()) :: map()
  def sample(sampler \\ __MODULE__), do: GenServer.call(sampler, :sample, @call_timeout)

  @impl true
  def init(options) do
    interval = Keyword.fetch!(options, :sample_interval_ms)
    room_supervisor = Keyword.fetch!(options, :room_supervisor)

    if is_integer(interval) and interval > 0 do
      state = %{sample_interval_ms: interval, room_supervisor: room_supervisor}
      {:ok, schedule_sample(state)}
    else
      {:stop, :invalid_sample_interval}
    end
  end

  @impl true
  def handle_call(:sample, _from, state) do
    measurements = collect(state.room_supervisor)
    Telemetry.runtime_sample(measurements)
    {:reply, measurements, state}
  end

  @impl true
  def handle_info(:sample, state) do
    state.room_supervisor
    |> collect()
    |> Telemetry.runtime_sample()

    {:noreply, schedule_sample(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp collect(room_supervisor) do
    room_counts = DynamicSupervisor.count_children(room_supervisor)

    %{
      active_rooms: Map.fetch!(room_counts, :active),
      memory_bytes: :erlang.memory(:total),
      run_queue: :erlang.statistics(:run_queue)
    }
  end

  defp schedule_sample(state) do
    Process.send_after(self(), :sample, state.sample_interval_ms)
    state
  end
end
