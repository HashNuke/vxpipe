defmodule Vxpipe.CallEngine.Recording.PreparedWriter do
  @moduledoc false
  use GenServer

  @supervisor Vxpipe.CallEngine.Recording.PreparedWriterSupervisor
  @timeout 1_000
  @derive {Inspect, only: [:source]}
  @enforce_keys [:source, :handle, :token]
  defstruct @enforce_keys

  def start(writer, stream, options) do
    with :ok <- validate(options),
         {:ok, source} <-
           DynamicSupervisor.start_child(@supervisor, {__MODULE__, {writer, stream, options}}),
         do: call(source, :prepared)
  end

  def start_link(args), do: GenServer.start_link(__MODULE__, args)

  def child_spec(args),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [args]}, restart: :temporary}

  def adopt(%__MODULE__{} = prepared), do: call(prepared.source, {:adopt, prepared.token})
  def discard(%__MODULE__{} = prepared), do: call(prepared.source, {:discard, prepared.token})
  def retire(%__MODULE__{} = prepared), do: call(prepared.source, {:retire, prepared.token})

  @impl true
  def init({writer, stream, options}) do
    with :ok <- validate(options),
         {:ok, handle} <-
           open(
             writer,
             stream,
             Keyword.put(Keyword.fetch!(options, :writer_options), :source, self())
           ) do
      recorder = Keyword.fetch!(options, :source)
      phase = Keyword.fetch!(options, :owner)
      deadline = Keyword.fetch!(options, :deadline_ms)

      state = %{
        prepared: %__MODULE__{source: self(), handle: handle, token: make_ref()},
        recorder: recorder,
        recorder_monitor: Process.monitor(recorder),
        phase_monitor: Process.monitor(phase),
        deadline: deadline,
        timer: Process.send_after(self(), :lease_expired, max(deadline - now(), 0)),
        adopted?: false
      }

      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:prepared, _from, state), do: {:reply, {:ok, state.prepared}, state}

  def handle_call(
        {:adopt, token},
        {recorder, _},
        %{recorder: recorder, prepared: %{token: token}} = state
      ) do
    cond do
      state.adopted? ->
        {:reply, :ok, state}

      state.deadline <= now() ->
        {:stop, :normal, {:error, :deadline_elapsed}, state}

      true ->
        Process.cancel_timer(state.timer)
        Process.demonitor(state.phase_monitor, [:flush])
        {:reply, :ok, %{state | adopted?: true, phase_monitor: nil, timer: nil}}
    end
  end

  def handle_call({:adopt, _token}, _from, state), do: {:reply, {:error, :not_owner}, state}

  def handle_call(
        {:discard, token},
        _from,
        %{prepared: %{token: token}, adopted?: false} = state
      ),
      do: {:stop, :normal, :ok, state}

  def handle_call({:discard, _token}, _from, state),
    do: {:reply, {:error, :stale_preparation}, state}

  def handle_call(
        {:retire, token},
        {recorder, _},
        %{recorder: recorder, prepared: %{token: token}} = state
      ),
      do: {:stop, :normal, :ok, state}

  def handle_call({:retire, _token}, _from, state), do: {:reply, {:error, :not_owner}, state}

  @impl true
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    if monitor in [state.recorder_monitor, state.phase_monitor],
      do: {:stop, :normal, state},
      else: {:noreply, state}
  end

  def handle_info(:lease_expired, %{adopted?: false} = state), do: {:stop, :normal, state}
  def handle_info(_message, state), do: {:noreply, state}

  defp validate(options) do
    deadline = Keyword.get(options, :deadline_ms)
    attempt = Keyword.get(options, :attempt_id)

    if is_pid(Keyword.get(options, :source)) and is_pid(Keyword.get(options, :owner)) and
         is_integer(deadline) and deadline > now() and is_binary(attempt) and
         byte_size(attempt) in 1..128, do: :ok, else: {:error, :invalid_preparation}
  end

  defp open(writer, stream, options) do
    case writer.open(stream, options) do
      {:ok, _handle} = success -> success
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_recording_writer_response}
    end
  catch
    _kind, _reason -> {:error, :recording_writer_unavailable}
  end

  defp call(source, message) do
    GenServer.call(source, message, @timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp now, do: System.monotonic_time(:millisecond)
end
