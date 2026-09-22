defmodule Vxpipe.CallEngine.Tool.InvocationRegistry do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  alias Vxpipe.CallEngine.Readiness.Resource

  alias Vxpipe.CallEngine.Tool.{
    Context,
    InvocationBinding,
    InvocationCompletion,
    InvocationLifecycle,
    InvocationRecord,
    InvocationSubmission,
    InvocationSupervisor,
    InvocationTelemetry,
    InvocationUsage
  }

  alias Vxpipe.CallEngine.Tool.InvocationRegistry.State

  @call_timeout 1_000

  def start_link(options) do
    genserver_options = Keyword.take(options, [:name])
    GenServer.start_link(__MODULE__, options, genserver_options)
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :activation_id)},
      start: {__MODULE__, :start_link, [options]}
    }
  end

  @spec submit(GenServer.server(), InvocationBinding.t(), map(), Context.t(), String.t()) ::
          {:accepted, :blocking | :non_blocking}
          | {:error, :rejected | :saturated | :unavailable}
  def submit(registry, binding, arguments, context, invocation_id) do
    with {:ok, submission} <- InvocationSubmission.new(binding, arguments, context, invocation_id) do
      admission_deadline = System.monotonic_time(:millisecond) + @call_timeout
      call_with_reconciliation(registry, submission, admission_deadline)
    else
      {:error, _reason} -> {:error, :rejected}
    end
  end

  @spec snapshot(GenServer.server(), timeout()) ::
          {:ok, [Vxpipe.CallEngine.Tool.InvocationStatus.t()]} | {:error, :unavailable}
  def snapshot(registry, timeout \\ @call_timeout) do
    safe_call(registry, :snapshot, timeout)
  end

  @impl Vxpipe.CallEngine.Readiness.Adapter
  def readiness(registry) do
    with {:ok, resource, status, supervisor} <- safe_call(registry, :readiness),
         %{active: _active} <- DynamicSupervisor.count_children(supervisor) do
      {:ok, resource, status}
    else
      _unavailable -> {:error, :unavailable}
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec lease_next(GenServer.server(), String.t()) ::
          {:ok, Vxpipe.CallEngine.Tool.CompletionLease.t()}
          | {:error, :empty | :unavailable}
  def lease_next(registry, consumer_id) when is_binary(consumer_id) and consumer_id != "" do
    safe_call(registry, {:lease_next, consumer_id})
  end

  def lease_next(_registry, _consumer_id), do: {:error, :unavailable}

  @spec release_completion(GenServer.server(), String.t(), reference()) ::
          :ok | {:error, :unavailable}
  def release_completion(registry, invocation_id, lease_id)
      when is_binary(invocation_id) and is_reference(lease_id) do
    safe_call(registry, {:release_completion, invocation_id, lease_id})
  end

  def release_completion(_registry, _invocation_id, _lease_id), do: {:error, :unavailable}

  @spec acknowledge_completion(GenServer.server(), String.t(), reference()) ::
          :ok | {:error, :unavailable}
  def acknowledge_completion(registry, invocation_id, lease_id)
      when is_binary(invocation_id) and is_reference(lease_id) do
    safe_call(registry, {:acknowledge_completion, invocation_id, lease_id})
  end

  def acknowledge_completion(_registry, _invocation_id, _lease_id),
    do: {:error, :unavailable}

  @impl true
  def init(options) do
    with {:ok, state} <- configuration(options) do
      {:ok, state}
    else
      _invalid -> {:stop, :invalid_configuration}
    end
  end

  @impl true
  def handle_call(:readiness, _from, %{readiness_resource: nil} = state) do
    {:reply, {:error, :unavailable}, state}
  end

  def handle_call(:readiness, _from, state) do
    {:reply, {:ok, state.readiness_resource, :ready, state.invocation_supervisor}, state}
  end

  def handle_call(
        {:submit, %InvocationSubmission{} = submission, admission_deadline},
        _from,
        state
      )
      when is_integer(admission_deadline) do
    case State.submission_outcome(state, submission) do
      {:accepted, mode} ->
        {:reply, {:accepted, mode}, state}

      {:error, :rejected} ->
        {:reply, {:error, :rejected}, state}

      {:error, :unavailable} ->
        if admission_open?(admission_deadline) do
          start_invocation(submission, state, admission_deadline)
        else
          InvocationTelemetry.admission(
            :unavailable,
            State.size(state),
            state.maximum_invocations
          )

          {:reply, {:error, :unavailable}, state}
        end
    end
  end

  def handle_call({:submission_outcome, %InvocationSubmission{} = submission}, _from, state) do
    {:reply, State.submission_outcome(state, submission), state}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, {:ok, State.statuses(state)}, state}
  end

  def handle_call({:lease_next, consumer_id}, _from, state) do
    case State.next_terminal(state) do
      {:ok, record} ->
        lease_id = make_ref()
        {:ok, record, lease} = InvocationRecord.lease(record, consumer_id, lease_id)
        {:reply, {:ok, lease}, State.replace(state, record)}

      :empty ->
        {:reply, {:error, :empty}, state}
    end
  end

  def handle_call({:release_completion, invocation_id, lease_id}, _from, state) do
    with {:ok, record} <- State.fetch(state, invocation_id),
         {:ok, record} <- InvocationRecord.release(record, lease_id) do
      state = State.replace(state, record)

      InvocationTelemetry.handoff(
        :queued,
        State.completion_depth(state),
        state.maximum_invocations
      )

      notify_completion(state, invocation_id)
      {:reply, :ok, state}
    else
      _missing_or_stale -> {:reply, {:error, :unavailable}, state}
    end
  end

  def handle_call({:acknowledge_completion, invocation_id, lease_id}, _from, state) do
    with {:ok, record} <- State.fetch(state, invocation_id),
         true <- InvocationRecord.leased_by?(record, lease_id) do
      state = State.consume(state, record)

      InvocationTelemetry.handoff(
        :consumed,
        State.completion_depth(state),
        state.maximum_invocations
      )

      {:reply, :ok, state}
    else
      _missing_or_stale -> {:reply, {:error, :unavailable}, state}
    end
  end

  @impl true
  def handle_info(
        {:vxpipe_tool_invocation_finished, worker, %InvocationCompletion{} = completion},
        state
      ) do
    case State.fetch(state, completion.invocation_id) do
      {:ok, %InvocationRecord{worker: ^worker, monitor: monitor} = record}
      when is_reference(monitor) ->
        Process.demonitor(monitor, [:flush])

        case InvocationRecord.finish(record, completion) do
          {:ok, record} ->
            state = State.replace(state, record)

            InvocationTelemetry.settled(record)

            InvocationTelemetry.handoff(
              :queued,
              State.completion_depth(state),
              state.maximum_invocations
            )

            InvocationLifecycle.settled(
              state.lifecycle_target,
              state.completion_target,
              record
            )

            InvocationUsage.settled(
              record,
              state.lifecycle_target,
              state.completion_target
            )

            notify_completion(state, record.invocation_id)
            {:noreply, state}

          {:error, :stale_completion} ->
            {:noreply, state}
        end

      _stale_or_missing ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, monitor, :process, _worker, _reason}, state) do
    case State.find_by_monitor(state, monitor) do
      {:ok, record} ->
        completion = InvocationRecord.failed_completion(record)
        {:ok, record} = InvocationRecord.finish(record, completion)
        state = State.replace(state, record)
        InvocationTelemetry.terminated(record)

        InvocationTelemetry.handoff(
          :queued,
          State.completion_depth(state),
          state.maximum_invocations
        )

        InvocationLifecycle.settled(state.lifecycle_target, state.completion_target, record)
        InvocationUsage.settled(record, state.lifecycle_target, state.completion_target)
        notify_completion(state, record.invocation_id)
        {:noreply, state}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp start_invocation(submission, state, admission_deadline) do
    if State.full?(state) do
      InvocationTelemetry.admission(
        :saturated,
        State.size(state),
        state.maximum_invocations
      )

      {:reply, {:error, :saturated}, state}
    else
      start_available_invocation(submission, state, admission_deadline)
    end
  end

  defp start_available_invocation(submission, state, admission_deadline) do
    options = [
      invocation_id: submission.invocation_id,
      binding: submission.binding,
      arguments: submission.arguments,
      context: submission.context,
      reply_to: self(),
      timeout_ms: state.invocation_timeout_ms,
      maximum_result_bytes: state.maximum_result_bytes
    ]

    case InvocationSupervisor.prepare_invocation(state.invocation_supervisor, options) do
      {:ok, worker} ->
        monitor = Process.monitor(worker)
        record = InvocationRecord.new(submission, worker, monitor)

        case begin_prepared_invocation(worker, admission_deadline) do
          :ok ->
            record =
              InvocationUsage.started(
                record,
                state.usage,
                state.lifecycle_target,
                state.completion_target
              )

            state = State.add(state, record)

            InvocationTelemetry.admission(
              :accepted,
              State.size(state),
              state.maximum_invocations
            )

            InvocationLifecycle.accepted(
              state.lifecycle_target,
              state.completion_target,
              submission
            )

            {:reply, {:accepted, submission.conversation_mode}, state}

          {:error, _reason} ->
            Process.demonitor(monitor, [:flush])
            _ = DynamicSupervisor.terminate_child(state.invocation_supervisor, worker)

            InvocationTelemetry.admission(
              :start_failed,
              State.size(state),
              state.maximum_invocations
            )

            {:reply, {:error, :unavailable}, state}
        end

      {:error, :max_children} ->
        InvocationTelemetry.admission(
          :saturated,
          State.size(state),
          state.maximum_invocations
        )

        {:reply, {:error, :saturated}, state}

      {:error, _reason} ->
        InvocationTelemetry.admission(
          :unavailable,
          State.size(state),
          state.maximum_invocations
        )

        {:reply, {:error, :unavailable}, state}
    end
  end

  defp begin_prepared_invocation(worker, admission_deadline) do
    if admission_open?(admission_deadline) do
      InvocationSupervisor.begin_invocation(worker, admission_deadline)
    else
      {:error, :unavailable}
    end
  end

  defp configuration(options) do
    with {:ok, options} <-
           Keyword.validate(options, [
             :activation_id,
             :participant_id,
             :name,
             :invocation_supervisor,
             :completion_target,
             :lifecycle_target,
             :maximum_invocations,
             :maximum_consumed_invocations,
             :invocation_timeout_ms,
             :maximum_result_bytes,
             :usage
           ]),
         activation_id when is_binary(activation_id) and activation_id != "" <-
           Keyword.get(options, :activation_id),
         participant_id when is_nil(participant_id) or is_binary(participant_id) <-
           Keyword.get(options, :participant_id),
         true <- participant_id != "",
         {:ok, invocation_supervisor} <-
           server_pid(Keyword.get(options, :invocation_supervisor)),
         {:ok, completion_target} <-
           server_pid(Keyword.get(options, :completion_target)),
         lifecycle_target when is_nil(lifecycle_target) or is_pid(lifecycle_target) <-
           Keyword.get(options, :lifecycle_target),
         maximum_invocations when is_integer(maximum_invocations) and maximum_invocations > 0 <-
           Keyword.get(options, :maximum_invocations),
         maximum_consumed when is_integer(maximum_consumed) and maximum_consumed > 0 <-
           Keyword.get(options, :maximum_consumed_invocations),
         invocation_timeout_ms
         when is_integer(invocation_timeout_ms) and invocation_timeout_ms > 0 <-
           Keyword.get(options, :invocation_timeout_ms),
         maximum_result_bytes
         when is_integer(maximum_result_bytes) and maximum_result_bytes > 0 <-
           Keyword.get(options, :maximum_result_bytes),
         {:ok, usage} <- InvocationUsage.configuration(Keyword.get(options, :usage)) do
      {:ok,
       %State{
         invocation_supervisor: invocation_supervisor,
         completion_target: completion_target,
         lifecycle_target: lifecycle_target,
         maximum_invocations: maximum_invocations,
         maximum_consumed_invocations: maximum_consumed,
         invocation_timeout_ms: invocation_timeout_ms,
         maximum_result_bytes: maximum_result_bytes,
         usage: usage,
         readiness_resource:
           readiness_resource(participant_id, activation_id, {options, invocation_supervisor})
       }}
    else
      _invalid -> {:error, :invalid_configuration}
    end
  end

  defp call_with_reconciliation(registry, submission, admission_deadline) do
    GenServer.call(registry, {:submit, submission, admission_deadline}, @call_timeout)
  catch
    :exit, _reason -> safe_reconcile(registry, submission)
  end

  defp admission_open?(deadline) do
    System.monotonic_time(:millisecond) < deadline
  end

  defp safe_reconcile(registry, submission) do
    GenServer.call(registry, {:submission_outcome, submission}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp safe_call(registry, message) do
    safe_call(registry, message, @call_timeout)
  end

  defp safe_call(registry, message, timeout) do
    GenServer.call(registry, message, timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp notify_completion(state, invocation_id) do
    send(state.completion_target, {:vxpipe_tool_completion_available, self(), invocation_id})
  end

  defp readiness_resource(nil, _activation_id, _configuration), do: nil

  defp readiness_resource(participant_id, activation_id, configuration) do
    Resource.new(:tool_invocations, {:participant, participant_id}, __MODULE__, configuration,
      binding: activation_id
    )
  end

  defp server_pid(server) do
    case GenServer.whereis(server) do
      pid when is_pid(pid) -> {:ok, pid}
      _missing -> {:error, :unavailable}
    end
  rescue
    _exception -> {:error, :unavailable}
  end
end
