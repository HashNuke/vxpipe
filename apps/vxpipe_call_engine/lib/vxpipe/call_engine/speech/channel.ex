defmodule Vxpipe.CallEngine.Speech.Channel do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.Speech.{
    Allocation,
    CapabilityTree,
    Event,
    Input,
    ProviderName,
    ScopeControl
  }

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
       pending_count: 0,
       input: nil
     }}
  end

  @impl true
  def handle_call({:command, allocation, deadline, message}, from, state) do
    cond do
      allocation != state.allocation ->
        {:reply, {:error, :not_owner}, state}

      deadline <= System.monotonic_time(:millisecond) ->
        {:reply, {:error, :command_timeout}, state}

      true ->
        execute(message, from, deadline, state)
    end
  end

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

  def handle_call({:input, allocation, command, audio}, {caller, _tag} = from, state) do
    cond do
      allocation != state.allocation or caller != state.consumer ->
        {:reply, {:error, :not_owner}, state}

      not Allocation.valid?(allocation) ->
        {:reply, {:error, :closed}, state}

      not state.active? ->
        {:reply, {:error, :not_ready}, state}

      command.deadline <= System.monotonic_time(:millisecond) ->
        {:reply, {:error, :command_timeout}, state}

      not is_nil(state.input) ->
        {:reply, {:error, :busy}, state}

      :atomics.compare_exchange(command.token, 1, 0, 1) != :ok ->
        {:reply, {:error, :command_timeout}, state}

      true ->
        timer = Process.send_after(self(), {:input_expired, command.ref}, remaining(command))
        input = %{command: command, from: from, timer: timer, claimed?: false}
        Input.submit(allocation, command, audio)
        {:noreply, %{state | input: input}}
    end
  end

  def handle_call({:claim_input, reference}, {worker, _tag}, state) do
    case state.input do
      %{command: %{ref: ^reference} = command, claimed?: false} = input ->
        if remaining(command) > 0 and Allocation.valid?(state.allocation) and
             worker == GenServer.whereis(Input.address(state.allocation)) do
          {:reply, {:ok, state.module, state.producer},
           %{state | input: %{input | claimed?: true}}}
        else
          {:reply, {:error, :closed}, state}
        end

      _input ->
        {:reply, {:error, :closed}, state}
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

  def handle_cast({:input_result, reference, worker, result}, state) do
    case state.input do
      %{command: %{ref: ^reference} = command, claimed?: true} = input ->
        cond do
          worker != GenServer.whereis(Input.address(state.allocation)) ->
            {:noreply, state}

          remaining(command) == 0 or result == {:error, :session_failed} ->
            input_failed(state)

          true ->
            Process.cancel_timer(input.timer)
            GenServer.reply(input.from, result)
            {:noreply, %{state | input: nil}}
        end

      _input ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:input_expired, reference}, %{input: %{command: %{ref: reference}}} = state),
    do: input_failed(state)

  def handle_info({:input_expired, _reference}, state), do: {:noreply, state}

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state)
      when monitor == state.producer_monitor or monitor == state.scope_monitor do
    retire(state.allocation)
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

  defp execute({:adopt, consumer, command}, {caller, _tag}, _deadline, state) do
    if caller == state.allocation.lease and state.prepared? and
         is_pid(consumer) and Process.alive?(consumer) and Allocation.pending?(state.allocation) and
         Allocation.valid?(state.allocation) do
      case ScopeControl.activate(state.allocation, caller, consumer, command) do
        :ok ->
          if remaining(command) > 0 and Allocation.valid?(state.allocation) do
            {:reply, :ok,
             dispatch(%{state | consumer: consumer, prepared?: false, active?: true})}
          else
            fail(state, :command_timeout)
          end

        {:error, :command_timeout} = error ->
          if :atomics.compare_exchange(command.token, 1, 0, 2) == 1,
            do: fail(state, :command_timeout),
            else: {:reply, error, state}

        error ->
          {:reply, error, state}
      end
    else
      {:reply, {:error, :not_adoptable}, state}
    end
  end

  defp execute(message, from, _deadline, state), do: handle_call(message, from, state)

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

    command = %{deadline: state.allocation.deadline, token: :atomics.new(1, [])}
    result = ScopeControl.activate(state.allocation, authority, consumer, command)

    if result == :ok and remaining(command) > 0 and Allocation.valid?(state.allocation) do
      dispatch(%{state | active?: true})
    else
      :atomics.compare_exchange(command.token, 1, 0, 2)
      retire(state.allocation)
      ScopeControl.failed(state.allocation, :startup_timeout)
      GenServer.cast(self(), :retire)
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

  defp input_failed(state) do
    retire(state.allocation)
    GenServer.reply(state.input.from, {:error, :session_failed})
    ScopeControl.failed(state.allocation, :session_failed)
    {:stop, :normal, state}
  end

  defp remaining(command),
    do: max(command.deadline - System.monotonic_time(:millisecond), 0)

  defp retire(allocation) do
    Allocation.cancel(allocation)

    case ProviderName.whereis_name(allocation) do
      :undefined -> :ok
      pid -> Process.exit(pid, :kill)
    end
  end

  defp fail(state, reason) do
    retire(state.allocation)
    ScopeControl.failed(state.allocation, reason)
    {:stop, :normal, {:error, reason}, state}
  end
end
