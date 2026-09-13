defmodule Vxpipe.Gateway.Media.SharedOutputPipeline do
  @moduledoc false
  use GenServer

  alias Vxpipe.Gateway.Media.OutputArbiter

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: via(Keyword.fetch!(options, :pipeline_id)))
  end

  def push(pipeline_id, frame), do: GenServer.call(via(pipeline_id), {:push, frame}, 5_000)

  @impl true
  def init(options) do
    output = Keyword.fetch!(options, :output_sink)
    owner = Keyword.fetch!(options, :owner)

    identity =
      options
      |> Keyword.take([:tenant_id, :room_id, :incarnation_id, :participant_id])
      |> Map.new()

    {:ok,
     %{
       output: output,
       owner: owner,
       pipeline_id: Keyword.fetch!(options, :pipeline_id),
       output_monitor: Process.monitor(output),
       owner_monitor: Process.monitor(owner),
       binding: nil,
       identity: identity
     }, {:continue, :bind}}
  end

  @impl true
  def handle_continue(:bind, state) do
    case OutputArbiter.bind_room(state.output, state.identity) do
      {:ok, binding} ->
        send(state.owner, {:vxpipe_room_audio_output_ready, state.pipeline_id})
        {:noreply, %{state | binding: binding}}

      {:error, _} ->
        {:stop, :output_unavailable, state}
    end
  end

  @impl true
  def handle_call({:push, frame}, _from, state) do
    case OutputArbiter.push_room(state.output, state.binding, frame) do
      :ok ->
        {:reply, :ok, state}

      :dropped ->
        discard(frame.timestamp, state)

      {:error, reason} when reason in [:held, :clearing, :draining, :stale_output_generation] ->
        discard(frame.timestamp, state)

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(
        {:vxpipe_room_output, output, binding, timestamp},
        %{output: output, binding: binding} = state
      ) do
    sent(timestamp, state)
    {:noreply, state}
  end

  def handle_info({:DOWN, monitor, :process, _, _}, state)
      when monitor == state.output_monitor or monitor == state.owner_monitor,
      do: {:stop, :output_unavailable, state}

  def handle_info(_, state), do: {:noreply, state}

  defp discard(timestamp, state) do
    sent(timestamp, state)
    {:reply, :ok, state}
  end

  defp sent(timestamp, state),
    do: send(state.owner, {:vxpipe_room_audio_output_sent, state.pipeline_id, timestamp})

  defp via(id), do: {:via, Registry, {Vxpipe.Gateway.Media.Registry, {:shared_room_output, id}}}
end
