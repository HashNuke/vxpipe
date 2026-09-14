defmodule Vxpipe.Gateway.Media.SharedOutputPipeline do
  @moduledoc false
  use GenServer

  alias Vxpipe.Gateway.Media.OutputArbiter

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: via(Keyword.fetch!(options, :pipeline_id)))
  end

  def push(pipeline_id, frame), do: GenServer.call(via(pipeline_id), {:push, frame}, 5_000)

  def activate(pipeline, resource, generation),
    do: GenServer.call(pipeline, {:activate, resource, generation}, 5_000)

  def discard(pipeline), do: GenServer.call(pipeline, :discard_preparation, 1_000)

  def readiness(pipeline) do
    with {:ok, output, token} <- GenServer.call(pipeline, :output_binding, 1_000),
         do: OutputArbiter.room_binding_readiness(output, token)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

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
       preparation: Keyword.get(options, :preparation),
       activated_generation: nil,
       identity: identity
     }, {:continue, :bind}}
  end

  @impl true
  def handle_continue(:bind, state) do
    case bind(state) do
      {:ok, binding} ->
        send(state.owner, {:vxpipe_room_audio_output_ready, state.pipeline_id})
        {:noreply, %{state | binding: binding}}

      {:error, _} ->
        {:stop, :output_unavailable, state}
    end
  end

  defp bind(%{preparation: nil} = state),
    do: OutputArbiter.bind_room(state.output, state.identity)

  defp bind(state),
    do: OutputArbiter.prepare_room(state.output, state.identity, state.preparation)

  @impl true
  def handle_call(:output_binding, _from, state) do
    {:reply, {:ok, state.output, state.binding}, state}
  end

  def handle_call(
        :discard_preparation,
        {owner, _},
        %{owner: owner, preparation: preparation} = state
      )
      when not is_nil(preparation) do
    {:reply, OutputArbiter.discard_room(state.output, state.binding), state}
  end

  def handle_call(:discard_preparation, _from, state),
    do: {:reply, {:error, :stale_preparation}, state}

  def handle_call({:activate, resource, generation}, {owner, _}, %{owner: owner} = state) do
    if state.preparation != nil or state.activated_generation == generation do
      case OutputArbiter.commit_room(state.output, resource, generation) do
        :ok -> {:reply, :ok, %{state | preparation: nil, activated_generation: generation}}
        {:error, _reason} = error -> {:reply, error, state}
      end
    else
      {:reply, {:error, :not_prepared}, state}
    end
  end

  def handle_call({:activate, _resource, _generation}, _from, state),
    do: {:reply, {:error, :not_owner}, state}

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
        {:vxpipe_room_binding_cancelled, output, binding},
        %{output: output, binding: binding, preparation: preparation} = state
      )
      when not is_nil(preparation),
      do: {:stop, :normal, state}

  def handle_info(
        {event, output, binding, timestamp},
        %{output: output, binding: binding} = state
      )
      when event in [:vxpipe_room_output, :vxpipe_room_output_discarded] do
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
