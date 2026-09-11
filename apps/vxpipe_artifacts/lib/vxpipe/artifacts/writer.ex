defmodule Vxpipe.Artifacts.Writer do
  @moduledoc false

  use GenServer

  alias Vxpipe.Artifacts.{ArtifactSpec, Chunk, Handoff, ObjectStore, Result}
  alias Vxpipe.Artifacts.Writer.{Progress, State}

  @call_timeout 1_000

  def start_link(options) do
    spec = Keyword.fetch!(options, :spec)
    GenServer.start_link(__MODULE__, options, name: via(spec))
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :spec).artifact_id},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      shutdown: 5_000
    }
  end

  @spec handoff(GenServer.server()) :: Handoff.t()
  def handoff(writer), do: GenServer.call(writer, :handoff, @call_timeout)

  @impl true
  def init(options) do
    with source when is_pid(source) <- Keyword.get(options, :source),
         %ArtifactSpec{} = spec <- Keyword.get(options, :spec),
         object_store when is_atom(object_store) <- Keyword.get(options, :object_store),
         true <- ObjectStore.valid?(object_store),
         {:ok, maximum} <- positive_integer(options, :maximum_pending_chunks),
         {:ok, drain_timeout_ms} <- positive_integer(options, :drain_timeout_ms),
         {:ok, observer} <- optional_pid(options, :observer) do
      handoff = Handoff.new(self(), maximum)

      state = %State{
        source_monitor: Process.monitor(source),
        handoff: handoff,
        spec: spec,
        object_store: object_store,
        object_store_options: Keyword.get(options, :object_store_options, []),
        observer: observer,
        drain_timeout_ms: drain_timeout_ms,
        pending: :queue.new(),
        progress: Progress.new()
      }

      {:ok, state, {:continue, :open}}
    else
      _invalid -> {:stop, :invalid_artifact_writer_options}
    end
  end

  @impl true
  def handle_continue(:open, state) do
    {:noreply,
     start_operation(state, :open, fn ->
       state.object_store.open(state.spec, state.object_store_options)
     end)}
  end

  @impl true
  def handle_call(:handoff, _from, state), do: {:reply, state.handoff, state}

  @impl true
  def handle_info(message, state) do
    case Handoff.message(state.handoff, message) do
      {:ok, chunk} -> state |> enqueue(chunk) |> continue()
      :error -> handle_non_handoff(message, state)
    end
  end

  defp handle_non_handoff(
         {reference, outcome},
         %State{task: %Task{ref: reference}} = state
       ) do
    Process.demonitor(reference, [:flush])

    state
    |> Map.put(:task, nil)
    |> finish_operation(outcome)
    |> continue_or_stop()
  end

  defp handle_non_handoff(
         {:DOWN, reference, :process, _pid, reason},
         %State{task: %Task{ref: reference}} = state
       ) do
    state
    |> Map.put(:task, nil)
    |> finish_operation({:error, {:object_store_task_exit, reason}})
    |> continue_or_stop()
  end

  defp handle_non_handoff(
         {:DOWN, reference, :process, _pid, reason},
         %State{source_monitor: reference, closing?: false} = state
       ) do
    Handoff.close(state.handoff)
    notify(state.observer, {:vxpipe_artifact_writer_draining, self()})
    timer = Process.send_after(self(), :drain_timeout, state.drain_timeout_ms)

    state
    |> Map.put(:closing?, true)
    |> Map.put(:source_monitor, nil)
    |> Map.put(:terminal_reason, reason)
    |> Map.put(:drain_timer, timer)
    |> continue()
  end

  defp handle_non_handoff(:drain_timeout, state) do
    terminate_task(state.task)
    abandoned = Handoff.abandon_pending(state.handoff)
    progress = Progress.fail(state.progress, abandoned)
    state = %{state | task: nil, current: nil, pending: :queue.new(), progress: progress}
    state |> Map.put(:terminal_reason, :drain_timeout) |> complete_or_finish()
  end

  defp handle_non_handoff(_message, state), do: {:noreply, state}

  defp enqueue(state, %Chunk{} = chunk) do
    %{state | pending: :queue.in(chunk, state.pending)}
  end

  defp continue(%State{task: %Task{}} = state), do: {:noreply, state}
  defp continue(%State{operation: :open} = state), do: {:noreply, state}

  defp continue(%State{upload: nil} = state) do
    finish_without_artifact(state, :object_store_unavailable)
  end

  defp continue(%State{current: nil} = state) do
    case :queue.out(state.pending) do
      {{:value, chunk}, pending} ->
        state = %{state | current: chunk, pending: pending}
        {:noreply, start_write(state)}

      {:empty, _pending} ->
        if state.closing? and Handoff.stats(state.handoff).pending == 0 do
          complete_or_finish(state)
        else
          {:noreply, state}
        end
    end
  end

  defp continue(state), do: {:noreply, state}

  defp continue_or_stop({:stop, _reason, _state} = stop), do: stop
  defp continue_or_stop(state), do: continue(state)

  defp start_write(state) do
    start_operation(state, :write, fn ->
      state.object_store.write_chunk(
        state.upload,
        state.current,
        state.object_store_options
      )
    end)
  end

  defp complete_or_finish(%State{upload: nil} = state) do
    finish_without_artifact(state, :object_store_unavailable)
  end

  defp complete_or_finish(state) do
    manifest = manifest(state)

    state =
      start_operation(state, {:complete, manifest}, fn ->
        state.object_store.complete(state.upload, manifest, state.object_store_options)
      end)

    {:noreply, state}
  end

  defp finish_operation(%State{operation: :open} = state, {:ok, upload}) do
    %{state | operation: nil, upload: upload}
  end

  defp finish_operation(%State{operation: :open} = state, {:error, _reason}) do
    Handoff.close(state.handoff)
    %{state | operation: nil, closing?: true, terminal_reason: :object_store_open_failed}
  end

  defp finish_operation(%State{operation: :write, current: chunk} = state, {:ok, upload}) do
    Handoff.acknowledge(state.handoff)

    %{
      state
      | operation: nil,
        upload: upload,
        current: nil,
        progress: Progress.accept(state.progress, chunk)
    }
  end

  defp finish_operation(%State{operation: :write} = state, {:error, _reason}) do
    Handoff.acknowledge(state.handoff)
    progress = Progress.fail(state.progress)
    %{state | operation: nil, current: nil, progress: progress}
  end

  defp finish_operation(
         %State{operation: {:complete, manifest}} = state,
         {:ok, artifact}
       ) do
    finish(state, %Result{manifest: manifest, artifact: artifact})
  end

  defp finish_operation(%State{operation: {:complete, manifest}} = state, {:error, _reason}) do
    manifest = %{manifest | status: :incomplete, terminal_reason: :completion_failed}
    finish(state, %Result{manifest: manifest, artifact: nil})
  end

  defp finish_operation(state, _invalid) do
    %{state | operation: nil, closing?: true, terminal_reason: :invalid_object_store_response}
  end

  defp finish_without_artifact(state, reason) do
    abandoned = Handoff.abandon_pending(state.handoff)
    progress = Progress.fail(state.progress, abandoned)
    state = %{state | progress: progress, terminal_reason: reason}
    finish(state, %Result{manifest: manifest(state), artifact: nil})
  end

  defp finish(state, %Result{} = result) do
    cancel_timer(state.drain_timer)
    notify(state.observer, {:vxpipe_artifact_writer_finished, self(), result})
    {:stop, :normal, state}
  end

  defp start_operation(state, operation, work) do
    task = Task.Supervisor.async_nolink(Vxpipe.Artifacts.WriterTaskSupervisor, work)
    %{state | task: task, operation: operation}
  end

  defp manifest(state) do
    Progress.manifest(state.progress, state.spec, state.handoff, state.terminal_reason)
  end

  defp positive_integer(options, key) do
    case Keyword.get(options, key) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _invalid -> {:error, key}
    end
  end

  defp optional_pid(options, key) do
    case Keyword.get(options, key) do
      nil -> {:ok, nil}
      value when is_pid(value) -> {:ok, value}
      _invalid -> {:error, key}
    end
  end

  defp notify(nil, _message), do: :ok
  defp notify(observer, message), do: send(observer, message)

  defp terminate_task(nil), do: :ok
  defp terminate_task(task), do: Task.shutdown(task, :brutal_kill)

  defp cancel_timer(nil), do: :ok

  defp cancel_timer(timer) do
    _result = Process.cancel_timer(timer)
    :ok
  end

  defp via(%ArtifactSpec{} = spec) do
    key = {:artifact_writer, spec.tenant_id, spec.call_id, spec.artifact_id}
    {:via, Registry, {Vxpipe.Artifacts.Registry, key}}
  end
end
