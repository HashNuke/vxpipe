defmodule Vxpipe.CallEngine.Speech.Channel do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.Speech.{Allocation, CapabilityTree, Event, ProviderName, ScopeControl}
  @maximum_pending 32

  def start_link(allocation),
    do: GenServer.start_link(__MODULE__, allocation, name: address(allocation))

  def address(allocation), do: CapabilityTree.address({allocation.generation, :channel})
  def bind(channel), do: GenServer.call(channel, :bind, 5_000)

  def configure(allocation, module, descriptor, timeout),
    do: GenServer.call(address(allocation), {:configure, module, descriptor, timeout}, 5_000)

  def started(allocation, pid), do: GenServer.call(address(allocation), {:started, pid}, 5_000)

  def emit(channel, kind, fields) do
    with {:ok, event} <- Event.build(kind, fields),
         do: GenServer.call(channel, {:emit, event}, 5_000)
  end

  @impl true
  def init(allocation) do
    {:ok,
     %{
       allocation: allocation,
       scope_monitor: Process.monitor(allocation.scope.control),
       producer: nil,
       producer_monitor: nil,
       consumer: allocation.consumer,
       descriptor: nil,
       module: nil,
       call_timeout: 5_000,
       started?: false,
       ready?: false,
       active?: false,
       prepared?: false,
       sequence: 0,
       awaiting: nil,
       pending: :queue.new(),
       pending_count: 0
     }}
  end

  @impl true
  def handle_call({:configure, module, descriptor, timeout}, _from, state),
    do: {:reply, :ok, %{state | module: module, descriptor: descriptor, call_timeout: timeout}}

  def handle_call(:bind, {producer, _tag}, %{producer: nil} = state) do
    if Allocation.valid?(state.allocation) and
         ProviderName.whereis_name(state.allocation) == producer do
      {:reply, :ok, %{state | producer: producer, producer_monitor: Process.monitor(producer)}}
    else
      {:reply, {:error, :closed}, state}
    end
  end

  def handle_call(:bind, _from, state), do: {:reply, {:error, :already_bound}, state}

  def handle_call({:started, producer}, _from, %{producer: producer} = state),
    do: {:reply, :ok, activate(%{state | started?: true})}

  def handle_call({:started, _producer}, _from, state), do: {:reply, {:error, :closed}, state}

  def handle_call(:metadata, {caller, _tag}, state) do
    cond do
      not Allocation.valid?(state.allocation) ->
        {:reply, {:error, :closed}, state}

      caller != state.consumer ->
        {:reply, {:error, :not_owner}, state}

      true ->
        {:reply,
         {:ok, Map.take(state, [:producer, :module, :descriptor, :call_timeout, :active?])},
         state}
    end
  end

  def handle_call({:adopt, consumer}, {caller, _tag}, state) do
    if caller == state.allocation.lease and state.prepared? and
         is_pid(consumer) and Process.alive?(consumer) and Allocation.pending?(state.allocation) and
         Allocation.valid?(state.allocation) do
      state = activate(%{state | consumer: consumer, prepared?: false})
      {:reply, if(state.active?, do: :ok, else: {:error, :closed}), state}
    else
      {:reply, {:error, :not_adoptable}, state}
    end
  end

  def handle_call({:emit, event}, {producer, _tag}, %{producer: producer} = state) do
    cond do
      not Allocation.valid?(state.allocation) ->
        {:reply, {:error, :closed}, state}

      state.pending_count >= @maximum_pending ->
        fail(state, :event_overflow)

      true ->
        event = %{
          event
          | session: state.allocation,
            generation: state.allocation.generation,
            producer: producer,
            sequence: state.sequence + 1
        }

        state = %{
          state
          | sequence: event.sequence,
            pending: :queue.in(event, state.pending),
            pending_count: state.pending_count + 1,
            ready?: state.ready? or event.kind == :ready
        }

        {:reply, :ok, activate(state)}
    end
  end

  def handle_call({:emit, _event}, _from, state), do: {:reply, {:error, :unbound_producer}, state}

  def handle_call({:ack, event}, {consumer, _tag}, %{consumer: consumer, awaiting: event} = state)
      when not is_nil(event) do
    if Allocation.valid?(state.allocation),
      do: {:reply, :ok, dispatch(%{state | awaiting: nil})},
      else: {:reply, {:error, :closed}, state}
  end

  def handle_call({:ack, _event}, _from, state), do: {:reply, {:error, :stale_event}, state}

  @impl true
  def handle_cast(:retire, state), do: {:stop, :normal, state}

  @impl true
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state)
      when monitor == state.producer_monitor or monitor == state.scope_monitor do
    Allocation.cancel(state.allocation)

    case ProviderName.whereis_name(state.allocation) do
      :undefined -> :ok
      pid -> Process.exit(pid, :kill)
    end

    {:stop, :normal, state}
  end

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :speech_channel)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp activate(
         %{started?: true, ready?: true, active?: false, consumer: nil, prepared?: false} = state
       ) do
    if Allocation.valid?(state.allocation) do
      send(state.allocation.lease, {:vxpipe_speech_prepared, state.allocation, state.descriptor})
      %{state | prepared?: true}
    else
      state
    end
  end

  defp activate(%{started?: true, ready?: true, active?: false, consumer: consumer} = state)
       when is_pid(consumer) do
    authority = state.allocation.lease || state.allocation.consumer

    if ScopeControl.activate(state.allocation, authority, consumer) == :ok do
      dispatch(%{state | active?: true})
    else
      state
    end
  end

  defp activate(state), do: dispatch(state)

  defp dispatch(%{active?: true, awaiting: nil, pending_count: count} = state) when count > 0 do
    if Allocation.valid?(state.allocation) do
      {{:value, event}, pending} = :queue.out(state.pending)
      send(state.consumer, {:vxpipe_speech, event})
      %{state | awaiting: event, pending: pending, pending_count: count - 1}
    else
      state
    end
  end

  defp dispatch(state), do: state

  defp fail(state, reason) do
    Allocation.cancel(state.allocation)
    ScopeControl.failed(state.allocation, reason)
    {:stop, :normal, {:error, reason}, state}
  end
end
