defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator do
  @moduledoc false

  use GenServer

  alias Vxpipe.AgentRuntime.Event

  alias Vxpipe.CallEngine.AgentRuntime.{
    CompletionContinuation,
    ConversationAdmission
  }

  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.{
    ActiveRequest,
    Configuration,
    History,
    Interruption,
    RequestOutcome,
    State
  }

  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.Telemetry

  @call_timeout 5_000
  @cancel_timeout 1_000

  def start_link(options) do
    genserver_options = Keyword.take(options, [:name])
    coordinator_options = Keyword.delete(options, :name)
    GenServer.start_link(__MODULE__, coordinator_options, genserver_options)
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :activation_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec respond(GenServer.server(), SendText.t()) ::
          :ok | {:error, :queue_full | :unavailable}
  def respond(coordinator, %SendText{} = command) do
    GenServer.call(coordinator, {:respond, command}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec interrupt(GenServer.server(), [History.identity()]) ::
          {:ok, [SendText.t()]} | {:error, :unavailable}
  def interrupt(coordinator, completed_turn_ids) when is_list(completed_turn_ids) do
    GenServer.call(coordinator, {:interrupt, completed_turn_ids}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @impl true
  def init(options) do
    case Configuration.new(options) do
      {:ok, state} -> {:ok, state}
      {:error, :invalid_configuration} -> {:stop, :invalid_configuration}
    end
  end

  @impl true
  def handle_call(
        {:respond, command},
        _from,
        %State{current: nil, completion_deferred?: true} = state
      ) do
    state = %{state | completion_deferred?: false}

    case admit(command, state) do
      {:ok, state} -> {:reply, :ok, state}
      {:held, state} -> {:reply, :ok, start_next(state)}
      {:error, :unavailable} -> {:reply, {:error, :unavailable}, state}
    end
  end

  def handle_call({:respond, command}, _from, %State{current: nil} = state) do
    case start_completion(state) do
      {:ok, state} ->
        respond_while_current(command, state)

      {:error, :empty} ->
        case admit(command, state) do
          {:ok, state} -> {:reply, :ok, state}
          {:held, state} -> {:reply, :ok, state}
          {:error, :unavailable} -> {:reply, {:error, :unavailable}, state}
        end

      {:error, :unavailable} ->
        {:reply, {:error, :unavailable}, state}
    end
  end

  def handle_call({:respond, command}, _from, %State{} = state) do
    respond_while_current(command, state)
  end

  def handle_call({:interrupt, completed_turn_ids}, _from, %State{} = state) do
    case Interruption.apply(state, completed_turn_ids, @cancel_timeout) do
      {:ok, interrupted, state} ->
        {:reply, {:ok, interrupted}, state}

      {:error, :unavailable, state} ->
        {:stop, :interruption_failed, {:error, :unavailable}, state}
    end
  end

  defp respond_while_current(command, state) do
    case ConversationAdmission.decide(state.invocation_registry) do
      :admit ->
        enqueue(command, state)

      :hold ->
        emit_holding_response(command, state)
        {:reply, :ok, state}

      {:error, :unavailable} ->
        {:reply, {:error, :unavailable}, state}
    end
  end

  @impl true
  def handle_info(
        {:vxpipe_tool_completion_available, _registry, _invocation_id},
        %State{current: nil, completion_deferred?: true} = state
      ) do
    {:noreply, state}
  end

  def handle_info(
        {:agent_runtime_event, %Event{kind: :request_started, correlation: correlation}},
        %State{
          current: %ActiveRequest{
            kind: {:completion, continuation},
            correlation: correlation,
            continuation_started?: false
          }
        } = state
      ) do
    send(
      state.owner,
      {:vxpipe_capability_continuation_started, self(), continuation.command}
    )

    {:noreply, %{state | current: ActiveRequest.mark_continuation_started(state.current)}}
  end

  def handle_info(
        {:agent_runtime_event,
         %Event{kind: :text_delta, correlation: correlation, data: %{text: text}}},
        %State{current: %ActiveRequest{correlation: correlation}} = state
      ) do
    case ActiveRequest.push(state.current, text) do
      {:ok, current, segments} ->
        state = %{state | current: current}
        state = observe_first_output(text, state)
        Enum.each(segments, &emit_text(state, &1))
        {:noreply, state}

      {:error, :invalid_response} ->
        state = cancel_runtime_request(state)

        state.current
        |> RequestOutcome.fail_uncommitted(:invalid_response, request_outcome_options(state))
        |> transition(state)
    end
  end

  def handle_info(
        {reference, result},
        %State{current: %ActiveRequest{task: %Task{ref: reference}}} = state
      ) do
    Process.demonitor(reference, [:flush])

    state.current
    |> RequestOutcome.finish(result, request_outcome_options(state))
    |> transition(state)
  end

  def handle_info(
        {:DOWN, reference, :process, _pid, _reason},
        %State{current: %ActiveRequest{task: %Task{ref: reference}}} = state
      ) do
    state.current
    |> RequestOutcome.fail_uncommitted(:provider_unavailable, request_outcome_options(state))
    |> transition(state)
  end

  def handle_info(
        {:vxpipe_tool_completion_available, registry, _invocation_id},
        %State{current: nil} = state
      ) do
    if current_registry?(registry, state) do
      {:noreply, start_next(state)}
    else
      {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp start_request(%SendText{} = command, %State{} = state) do
    case ActiveRequest.start_caller(command, request_options(state)) do
      {:ok, current} -> {:ok, %{state | current: current}}
      {:error, :unavailable} = error -> error
    end
  end

  defp start_next(%State{} = state) do
    case start_completion(state) do
      {:ok, state} -> state
      {:error, :empty} -> start_next_caller(state)
      {:error, :unavailable} -> exit(:completion_lease_unavailable)
    end
  end

  defp start_next_caller(%State{} = state) do
    case :queue.out(state.pending) do
      {{:value, command}, pending} ->
        state = %{state | pending: pending}

        case admit(command, state) do
          {:ok, state} ->
            state

          {:held, state} ->
            start_next(state)

          {:error, :unavailable} ->
            send(state.owner, {:vxpipe_capability_failed, self(), command, :provider_unavailable})
            start_next(state)
        end

      {:empty, _pending} ->
        state
    end
  end

  defp start_completion(state) do
    case CompletionContinuation.lease_next(
           state.invocation_registry,
           state.completion_consumer_id
         ) do
      {:ok, continuation} -> start_completion_request(continuation, state)
      {:error, reason} when reason in [:empty, :unavailable] -> {:error, reason}
    end
  end

  defp start_completion_request(continuation, state) do
    case ActiveRequest.start_completion(continuation, request_options(state)) do
      {:ok, current} -> {:ok, %{state | current: current}}
      {:error, :unavailable} -> release_unstarted_completion(continuation, state)
    end
  end

  defp release_unstarted_completion(continuation, state) do
    _ = CompletionContinuation.release(state.invocation_registry, continuation)
    {:error, :unavailable}
  end

  defp admit(command, state) do
    case ConversationAdmission.decide(state.invocation_registry) do
      :admit ->
        start_request(command, state)

      :hold ->
        emit_holding_response(command, state)
        {:held, state}

      {:error, :unavailable} ->
        {:error, :unavailable}
    end
  end

  defp enqueue(command, state) do
    if :queue.len(state.pending) < state.maximum_pending_requests do
      {:reply, :ok, %{state | pending: :queue.in(command, state.pending)}}
    else
      {:reply, {:error, :queue_full}, state}
    end
  end

  defp emit_holding_response(command, state) do
    send(
      state.owner,
      {:vxpipe_capability_text, self(), command, ConversationAdmission.holding_response()}
    )

    send(state.owner, {:vxpipe_capability_text_complete, self(), command})
  end

  defp transition(:advance, state),
    do: {:noreply, state |> Map.put(:current, nil) |> start_next()}

  defp transition({:advance, {:completed, command, correlation}}, state) do
    history = History.record(state.history, command, correlation)
    {:noreply, state |> Map.put(:current, nil) |> Map.put(:history, history) |> start_next()}
  end

  defp transition({:stop, reason}, state), do: {:stop, reason, %{state | current: nil}}

  defp observe_first_output(text, state)
       when is_binary(text) do
    case ActiveRequest.observe_output(state.current, text) do
      {current, :first} ->
        Telemetry.model_first_token(current.started_at, state.provider)
        %{state | current: current}

      {_current, :subsequent} ->
        state
    end
  end

  defp emit_text(state, text) do
    send(state.owner, {:vxpipe_capability_text, self(), state.current.command, text})
  end

  defp cancel_runtime_request(%State{current: %ActiveRequest{} = current} = state) do
    :ok = ActiveRequest.cancel(current, state.session, @cancel_timeout)
    state
  end

  defp current_registry?(registry, state) when is_pid(registry) do
    GenServer.whereis(state.invocation_registry) == registry
  rescue
    _exception -> false
  end

  defp current_registry?(_registry, _state), do: false

  defp request_options(state) do
    [
      agent_participant_id: state.agent_participant_id,
      invocation_registry: state.invocation_registry,
      maximum_output_bytes: state.maximum_output_bytes,
      request_supervisor: state.request_supervisor,
      session: state.session
    ]
  end

  defp request_outcome_options(state) do
    [
      invocation_registry: state.invocation_registry,
      owner: state.owner,
      provider: state.provider
    ]
  end
end
