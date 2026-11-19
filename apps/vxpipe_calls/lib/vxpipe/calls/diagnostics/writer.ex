defmodule Vxpipe.Calls.Diagnostics.Writer do
  @moduledoc "Isolated bounded diagnostic persistence with finite attempts and drain deadlines."
  use GenServer
  alias Vxpipe.Calls.Diagnostics.{AdmissionGate, Handoff, Write}

  def start_link(gate, options), do: start_link(Keyword.put(options, :admission_gate, gate))

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}, restart: :temporary}

  def handoff(writer), do: GenServer.call(writer, :handoff, 1_000)
  def drain(writer), do: GenServer.call(writer, :drain, 1_000)

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)

    state = %{
      handoff:
        Handoff.new(
          self(),
          Keyword.get(options, :maximum_count, 128),
          Keyword.get(options, :maximum_bytes, 1_048_576)
        ),
      admission_gate:
        Keyword.get_lazy(options, :admission_gate, fn ->
          AdmissionGate.new(Keyword.get(options, :maximum_count, 128))
        end),
      owner_monitor:
        if(Keyword.get(options, :owner), do: Process.monitor(Keyword.fetch!(options, :owner))),
      repository: Keyword.fetch!(options, :repository),
      task_supervisor: Keyword.fetch!(options, :task_supervisor),
      observer: Keyword.get(options, :observer),
      queue: :queue.new(),
      current: nil,
      task: nil,
      timer: nil,
      retry_token: nil,
      draining?: false,
      maximum_attempts: bounded!(options, :maximum_attempts, 2, 1..5),
      attempt_timeout_ms: bounded!(options, :attempt_timeout_ms, 1_000, 1..30_000),
      retry_delay_ms: bounded!(options, :retry_delay_ms, 50, 1..1_000),
      drain_timeout_ms: bounded!(options, :drain_timeout_ms, 2_000, 1..30_000)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:handoff, _from, state), do: {:reply, state.handoff, state}

  def handle_call(:drain, _from, state) do
    Handoff.close(state.handoff)

    if state.draining? do
      {:reply, :ok, state}
    else
      Process.send_after(self(), :drain_deadline, state.drain_timeout_ms)
      send(self(), :check_drained)
      {:reply, :ok, %{state | draining?: true}}
    end
  end

  @impl true
  def handle_info(
        {:diagnostic_write, token, id, %Write{} = write, bytes},
        %{handoff: %{token: token}} = state
      ) do
    item = %{id: id, write: write, bytes: bytes, attempt: 0}
    {:noreply, start_next(%{state | queue: :queue.in(item, state.queue)})}
  end

  def handle_info({reference, result}, %{task: %Task{ref: reference}} = state) do
    Process.demonitor(reference, [:flush])
    state = clear_task(state)

    if Write.success?(state.current.write, result),
      do: settle(state, :stored),
      else: retry_or_discard(state)
  end

  def handle_info(
        {:DOWN, reference, :process, _pid, _reason},
        %{task: %Task{ref: reference}} = state
      ),
      do: state |> clear_task() |> retry_or_discard()

  def handle_info({:attempt_timeout, reference}, %{task: %Task{ref: reference}} = state) do
    Task.shutdown(state.task, :brutal_kill)
    state |> clear_task() |> retry_or_discard()
  end

  def handle_info({:retry, token}, %{retry_token: token, task: nil} = state)
      when not is_nil(token),
      do: {:noreply, start_attempt(%{state | retry_token: nil})}

  def handle_info(:check_drained, %{draining?: true} = state) do
    if Handoff.stats(state.handoff).pending_count == 0,
      do: {:stop, :normal, state},
      else: {:noreply, state}
  end

  def handle_info(:drain_deadline, %{draining?: true} = state) do
    if state.task, do: Task.shutdown(state.task, :brutal_kill)
    Handoff.abandon(state.handoff)
    {:stop, :normal, %{state | task: nil}}
  end

  def handle_info(
        {:DOWN, reference, :process, _owner, _reason},
        %{owner_monitor: reference} = state
      ) do
    Handoff.close(state.handoff)

    unless state.draining? do
      Process.send_after(self(), :drain_deadline, state.drain_timeout_ms)
      send(self(), :check_drained)
    end

    {:noreply, %{state | draining?: true}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Handoff.close(state.handoff)
    if state.task, do: Task.shutdown(state.task, :brutal_kill)
    Handoff.abandon(state.handoff)
  end

  defp start_next(%{current: nil} = state) do
    case :queue.out(state.queue) do
      {{:value, item}, queue} -> start_attempt(%{state | current: item, queue: queue})
      {:empty, _queue} -> state
    end
  end

  defp start_next(state), do: state

  defp start_attempt(state) do
    write = state.current.write
    repository = state.repository
    supervisor = state.task_supervisor
    # The linked helper is owned by this writer. Only the database task is admitted
    # through the bounded Task.Supervisor; its public startup call can wait forever.
    # Timing the helper keeps both admission and execution inside the deadline.
    gate = state.admission_gate
    task = Task.async(fn -> run_attempt(gate, supervisor, write, repository) end)
    timer = Process.send_after(self(), {:attempt_timeout, task.ref}, state.attempt_timeout_ms)

    %{
      state
      | task: task,
        timer: timer,
        current: %{state.current | attempt: state.current.attempt + 1}
    }
  end

  defp run_attempt(gate, supervisor, write, repository) do
    with :ok <- AdmissionGate.reserve(gate) do
      task = admit_task(gate, supervisor, write, repository)
      Task.await(task, :infinity)
    end
  rescue
    _error in RuntimeError -> {:error, :diagnostics_unavailable}
  catch
    :exit, _reason -> {:error, :diagnostics_unavailable}
  end

  defp admit_task(gate, supervisor, write, repository) do
    Task.Supervisor.async(supervisor, fn -> Write.run(write, repository) end)
  after
    # A killed helper cannot execute after: keep its permit reserved because the
    # queued startup has an unknown outcome. Only a pool restart resets that debt.
    AdmissionGate.release(gate)
  end

  defp clear_task(state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    %{state | task: nil, timer: nil}
  end

  defp retry_or_discard(state) do
    if state.current.attempt < state.maximum_attempts do
      Handoff.retry(state.handoff)
      token = make_ref()
      Process.send_after(self(), {:retry, token}, state.retry_delay_ms)
      {:noreply, %{state | retry_token: token}}
    else
      settle(state, :discarded)
    end
  end

  defp settle(state, outcome) do
    Handoff.release(state.handoff, state.current.bytes, outcome)
    if state.observer, do: send(state.observer, {:diagnostic_settled, self(), outcome})
    state = start_next(%{state | current: nil})
    if state.draining?, do: send(self(), :check_drained)
    {:noreply, state}
  end

  defp bounded!(options, key, default, range) do
    value = Keyword.get(options, key, default)

    if is_integer(value) and value in range,
      do: value,
      else: raise(ArgumentError, "invalid diagnostic writer option")
  end
end
