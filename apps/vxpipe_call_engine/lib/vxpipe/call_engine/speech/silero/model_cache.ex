defmodule Vxpipe.CallEngine.Speech.Silero.ModelCache do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.Speech.Silero.Model

  def start_link(options),
    do:
      GenServer.start_link(__MODULE__, Keyword.get(options, :load, &Model.load/0),
        name: Keyword.fetch!(options, :name)
      )

  # Only the public immutable model resource crosses this cache. PCM, recurrent
  # stream state, inference tasks and speech allocation authority remain local.
  def fetch(server \\ __MODULE__, timeout \\ 5_000) do
    GenServer.call(server, {:fetch, System.monotonic_time(:millisecond) + timeout}, timeout)
  catch
    :exit, _ -> {:error, :model_unavailable}
  end

  @impl true
  def init(loader), do: {:ok, %{loader: loader, model: nil, task: nil, waiting: %{}}}

  @impl true
  def handle_call({:fetch, deadline}, from, state) do
    remaining = deadline - System.monotonic_time(:millisecond)

    cond do
      remaining <= 0 ->
        {:reply, {:error, :model_unavailable}, state}

      state.model ->
        {:reply, {:ok, state.model}, state}

      true ->
        task = state.task || Task.async(fn -> load(state.loader) end)
        monitor = :erlang.monitor(:process, elem(from, 0), [{:tag, {:waiter_down, from}}])
        timer = Process.send_after(self(), {:expire, from}, remaining)

        {:noreply,
         %{state | task: task, waiting: Map.put(state.waiting, from, {deadline, timer, monitor})}}
    end
  end

  defp load(loader) do
    case loader.() do
      {:ok, %Model{}} = result -> result
      _ -> {:error, :model_unavailable}
    end
  catch
    _, _ -> {:error, :model_unavailable}
  end

  @impl true
  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    now = System.monotonic_time(:millisecond)

    for {from, {deadline, timer, monitor}} <- state.waiting do
      Process.demonitor(monitor, [:flush])
      Process.cancel_timer(timer)
      GenServer.reply(from, if(now < deadline, do: result, else: {:error, :model_unavailable}))
    end

    model =
      case result do
        {:ok, model} -> model
        _ -> nil
      end

    {:noreply, %{state | model: model, task: nil, waiting: %{}}}
  end

  def handle_info({:expire, from}, state) do
    case Map.pop(state.waiting, from) do
      {nil, _} ->
        {:noreply, state}

      {{_, _, monitor}, waiting} ->
        Process.demonitor(monitor, [:flush])
        GenServer.reply(from, {:error, :model_unavailable})
        {:noreply, %{state | waiting: waiting}}
    end
  end

  def handle_info({{:waiter_down, from}, monitor, :process, _, _}, state) do
    case Map.pop(state.waiting, from) do
      {{_, timer, ^monitor}, waiting} ->
        Process.cancel_timer(timer)
        {:noreply, %{state | waiting: waiting}}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, %{model_loaded?: match?(%Model{}, status.state.model)})
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end
end
