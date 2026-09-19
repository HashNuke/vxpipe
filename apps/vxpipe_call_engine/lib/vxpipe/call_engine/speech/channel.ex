defmodule Vxpipe.CallEngine.Speech.Channel do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.Speech.Event

  @maximum_pending 32
  @timeout 5_000

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: address(Keyword.fetch!(options, :session)))
  end

  def address(session), do: {:via, Registry, {Vxpipe.CallEngine.Speech.Registry, session}}
  def bind(channel), do: GenServer.call(channel, :bind, @timeout)
  def activate(session), do: GenServer.call(address(session), :activate, @timeout)

  def emit(channel, kind, fields) do
    with {:ok, event} <- Event.build(kind, fields) do
      GenServer.call(channel, {:emit, event}, @timeout)
    end
  end

  @impl true
  def init(options) do
    session = Keyword.fetch!(options, :session)
    owner = Keyword.fetch!(options, :owner)
    monitor = Process.monitor(owner)
    timer = Process.send_after(self(), :startup_timeout, Keyword.fetch!(options, :start_timeout))

    metadata = %{
      owner: owner,
      provider: nil,
      module: Keyword.fetch!(options, :provider),
      descriptor: Keyword.fetch!(options, :descriptor),
      call_timeout: Keyword.fetch!(options, :call_timeout),
      active?: false
    }

    Registry.update_value(Vxpipe.CallEngine.Speech.Registry, session, fn _value -> metadata end)

    {:ok,
     %{
       session: session,
       owner: owner,
       monitor: monitor,
       timer: timer,
       generation: make_ref(),
       producer: nil,
       active?: false,
       sequence: 0,
       awaiting: nil,
       pending: :queue.new(),
       pending_count: 0
     }}
  end

  @impl true
  def handle_call(:bind, {producer, _tag}, %{producer: nil} = state) do
    update_metadata(state, &%{&1 | provider: producer})
    {:reply, :ok, %{state | producer: producer}}
  end

  def handle_call(:bind, _from, state), do: {:reply, {:error, :already_bound}, state}

  def handle_call(:activate, _from, state) do
    Process.cancel_timer(state.timer)
    update_metadata(state, &%{&1 | active?: true})
    {:reply, :ok, dispatch(%{state | active?: true})}
  end

  def handle_call({:emit, event}, {producer, _tag}, %{producer: producer} = state) do
    if state.pending_count < @maximum_pending do
      event = %{
        event
        | session: state.session,
          generation: state.generation,
          producer: producer,
          sequence: state.sequence + 1
      }

      state = %{
        state
        | sequence: event.sequence,
          pending: :queue.in(event, state.pending),
          pending_count: state.pending_count + 1
      }

      {:reply, :ok, dispatch(state)}
    else
      fail(state, :event_overflow)
      {:stop, :normal, {:error, :event_overflow}, state}
    end
  end

  def handle_call({:emit, _event}, _from, state),
    do: {:reply, {:error, :unbound_producer}, state}

  def handle_call({:ack, event}, {owner, _tag}, %{owner: owner, awaiting: event} = state)
      when not is_nil(event) do
    {:reply, :ok, dispatch(%{state | awaiting: nil})}
  end

  def handle_call({:ack, _event}, _from, state),
    do: {:reply, {:error, :stale_event}, state}

  @impl true
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{monitor: monitor} = state) do
    retire(state)
    {:stop, :normal, state}
  end

  def handle_info(:startup_timeout, %{active?: false} = state) do
    fail(state, :startup_timeout)
    {:stop, :normal, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :speech_channel)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp dispatch(%{active?: true, awaiting: nil, pending_count: count} = state) when count > 0 do
    {{:value, event}, pending} = :queue.out(state.pending)
    send(state.owner, {:vxpipe_speech, event})
    %{state | awaiting: event, pending: pending, pending_count: count - 1}
  end

  defp dispatch(state), do: state

  defp update_metadata(state, fun),
    do: Registry.update_value(Vxpipe.CallEngine.Speech.Registry, state.session, fun)

  defp fail(state, reason) do
    send(state.owner, {:vxpipe_speech_closed, state.session, reason})
    retire(state)
  end

  defp retire(state) do
    update_metadata(state, &%{&1 | active?: false})
    # Keep the starting supervisor alive until bounded OTP startup can kill a
    # child whose PID is not yet bound. Killing that parent prematurely would
    # strand an initializing child that traps exits.
    if is_pid(state.producer), do: Process.exit(state.producer, :kill)
  end
end
