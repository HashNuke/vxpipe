defmodule Vxpipe.CallEngine.AgentRuntime.Coordinator do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  alias Vxpipe.AgentRuntime.Event

  alias Vxpipe.CallEngine.AgentRuntime.{
    CompletionContinuation,
    Readiness
  }

  alias Vxpipe.CallEngine.AgentRuntime.Coordinator.{
    ActiveRequest,
    CompactionUsage,
    Configuration,
    HeldOutput,
    History,
    IdlePause,
    Interruption,
    LiteralOutput,
    ModelUsage,
    OutputSettlement,
    RequestOutcome,
    SourceRetirement,
    State,
    UsageRounds
  }

  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.Tool.ConversationAdmission
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

  @impl Vxpipe.CallEngine.Readiness.Adapter
  defdelegate readiness(coordinator), to: Readiness

  @spec respond(GenServer.server(), SendText.t()) ::
          :ok | {:error, :busy | :queue_full | :unavailable}
  def respond(coordinator, %SendText{} = command) do
    GenServer.call(coordinator, {:respond, command}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec generated_greeting(GenServer.server(), SendText.t()) ::
          :ok | {:error, :busy | :unavailable}
  def generated_greeting(coordinator, %SendText{} = command) do
    GenServer.call(coordinator, {:generated_greeting, command}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec fixed_greeting(GenServer.server(), SendText.t(), String.t()) ::
          :ok | {:error, :busy | :unavailable}
  def fixed_greeting(coordinator, %SendText{} = command, text) when is_binary(text) do
    GenServer.call(coordinator, {:fixed_greeting, command, text}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec caller_idle(GenServer.server(), SendText.t()) ::
          :ok | {:error, :busy | :unavailable}
  def caller_idle(coordinator, %SendText{} = command) do
    GenServer.call(coordinator, {:caller_idle, command}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec interrupt(GenServer.server(), [History.identity()]) ::
          {:ok, [SendText.t()]} | {:error, :unavailable}
  def interrupt(coordinator, completed_turn_ids, participant_id \\ nil, connection_id \\ nil)
      when is_list(completed_turn_ids) do
    GenServer.call(
      coordinator,
      {:interrupt, completed_turn_ids, participant_id, connection_id},
      @call_timeout
    )
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def interrupt_untracked(coordinator, participant_id, connection_id) do
    GenServer.call(
      coordinator,
      {:interrupt_untracked, participant_id, connection_id},
      @call_timeout
    )
  catch
    :exit, _ -> {:error, :unavailable}
  end

  def continuation_active?(coordinator, command) do
    GenServer.call(coordinator, {:continuation_active?, command}, @call_timeout)
  catch
    :exit, _ -> false
  end

  def retire_source(coordinator, participant_id, connection_id \\ nil, visible_commands \\ []) do
    GenServer.call(
      coordinator,
      {:retire_source, participant_id, connection_id, visible_commands},
      @call_timeout
    )
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec settle_output(GenServer.server(), struct(), String.t() | nil) ::
          :ok | :ignored | {:error, :unavailable}
  def settle_output(coordinator, command, text) do
    GenServer.call(coordinator, {:settle_output, command, text}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @doc """
  Returns a bounded provisional description of in-flight audio for model context.

  Never blocks the caller on session or worker work; returns nil when no
  output is outstanding or the coordinator is unavailable.
  """
  @spec in_flight_audio(GenServer.server(), map(), timeout()) :: map() | nil
  def in_flight_audio(coordinator, correlation, timeout) do
    GenServer.call(coordinator, {:in_flight_audio, correlation}, timeout)
  catch
    :exit, _reason -> nil
  end

  @impl true
  def init(options) do
    case Configuration.new(options) do
      {:ok, state} -> {:ok, state}
      {:error, :invalid_configuration} -> {:stop, :invalid_configuration}
    end
  end

  @impl true
  def handle_call(:readiness_binding, _from, state) do
    {:reply, Readiness.binding(state), state}
  end

  def handle_call({:settle_output, command, text}, _from, state) do
    case OutputSettlement.settle(state, command, text) do
      {:ok, state} ->
        case HeldOutput.release(state, command, &finish_or_hold/2) do
          {:stop, reason, state} -> {:stop, reason, {:error, :unavailable}, state}
          state -> {:reply, :ok, start_next(state)}
        end

      :ignored ->
        {:reply, :ignored, state}

      {:error, :unavailable} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:in_flight_audio, correlation}, _from, state) do
    {:reply, OutputSettlement.in_flight_description(state, correlation), state}
  end

  def handle_call({:respond, command}, _from, %State{pending_literal: literal} = state)
      when not is_nil(literal), do: enqueue(command, state)

  def handle_call({:respond, command}, _from, %State{awaiting_output: pending} = state)
      when not is_nil(pending), do: enqueue(command, state)

  def handle_call({:respond, command}, _from, %State{current: nil, idle_pause: pause} = state)
      when not is_nil(pause) do
    case enqueue(command, state) do
      {:reply, :ok, state} -> {:reply, :ok, start_next(state)}
      reply -> reply
    end
  end

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

      {:held, state} ->
        {:reply, {:error, :busy}, state}

      {:empty, state} ->
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

  def handle_call(
        {:generated_greeting, command},
        _from,
        %State{current: nil, awaiting_output: nil, pending_literal: nil} = state
      ) do
    case ActiveRequest.start_greeting(command, State.request_options(state)) do
      {:ok, current} -> {:reply, :ok, put_current(state, current)}
      {:error, :unavailable} -> {:reply, {:error, :unavailable}, state}
    end
  end

  def handle_call({:generated_greeting, _command}, _from, %State{} = state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call(
        {:fixed_greeting, command, text},
        _from,
        %State{current: nil, awaiting_output: nil, pending_literal: nil} = state
      ) do
    case LiteralOutput.start(state, command, text, :greeting) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, _} -> {:reply, {:error, :unavailable}, state}
    end
  end

  def handle_call({:fixed_greeting, _command, _text}, _from, %State{} = state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call(
        {:caller_idle, command},
        _from,
        %State{current: nil, awaiting_output: nil, pending_literal: nil} = state
      ) do
    case ActiveRequest.start_caller_idle(command, State.request_options(state)) do
      {:ok, current} -> {:reply, :ok, put_current(state, current)}
      {:error, :unavailable} -> {:reply, {:error, :unavailable}, state}
    end
  end

  def handle_call({:caller_idle, _command}, _from, %State{} = state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call({:continuation_active?, command}, _from, state) do
    active? =
      state.reply_protocol != :mode_message_v1 or state.history_mode != :host_settled or
        match?(%{command: ^command}, state.current) or
        match?(%{command: ^command}, state.awaiting_output)

    {:reply, active?, state}
  end

  def handle_call(
        {:interrupt_untracked, participant_id, connection_id},
        _from,
        %State{reply_protocol: :mode_message_v1, history_mode: :host_settled} = state
      ) do
    matches? = fn command ->
      is_struct(command, Vxpipe.CallEngine.Command.ContinueAgent) and
        command.participant_id == participant_id and command.connection_id == connection_id
    end

    with {:ok, state} <- SourceRetirement.cancel(state, matches?, @cancel_timeout),
         :ok <-
           Vxpipe.CallEngine.Tool.InvocationRegistry.update_source(
             state.invocation_registry,
             participant_id,
             connection_id,
             :interrupt
           ),
         {:ok, state} <- SourceRetirement.settle(state, matches?, [], &finish_or_hold/2) do
      {:reply, :ok, state}
    else
      {:stop, reason, state} -> {:stop, reason, {:error, :unavailable}, state}
      {:error, :unavailable} -> {:reply, {:error, :unavailable}, state}
    end
  end

  def handle_call({:interrupt_untracked, _, _}, _from, state), do: {:reply, :ok, state}

  def handle_call({:retire_source, _participant, connection_id, _visible}, _from, state)
      when is_binary(connection_id) and state.reply_protocol != :mode_message_v1,
      do: {:reply, :ok, state}

  def handle_call({:retire_source, participant_id, connection_id, visible}, _from, state) do
    retired? = fn command ->
      command.participant_id == participant_id and
        (is_nil(connection_id) or command.connection_id == connection_id)
    end

    state =
      if state.pending_literal && retired?.(state.pending_literal.command),
        do: LiteralOutput.cancel(state),
        else: state

    pending = :queue.filter(&(not retired?.(&1)), state.pending)
    state = %{state | pending: pending}

    with {:ok, state} <- SourceRetirement.cancel(state, retired?, @cancel_timeout),
         :ok <-
           Vxpipe.CallEngine.Tool.InvocationRegistry.update_source(
             state.invocation_registry,
             participant_id,
             connection_id,
             :detach
           ),
         {:ok, state} <- SourceRetirement.settle(state, retired?, visible, &finish_or_hold/2) do
      {:reply, :ok, start_next(state)}
    else
      {:stop, reason, state} -> {:stop, reason, {:error, :unavailable}, state}
      {:error, :unavailable} -> {:reply, {:error, :unavailable}, state}
    end
  end

  def handle_call(
        {:interrupt, completed_turn_ids, participant_id, connection_id},
        _from,
        %State{} = state
      ) do
    case Interruption.apply(state, completed_turn_ids, @cancel_timeout) do
      {:ok, interrupted, state} ->
        if state.reply_protocol == :mode_message_v1 and is_binary(participant_id) do
          :ok =
            Vxpipe.CallEngine.Tool.InvocationRegistry.update_source(
              state.invocation_registry,
              participant_id,
              connection_id,
              :interrupt
            )
        end

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
        {:ok, state} =
          LiteralOutput.start(state, command, ConversationAdmission.holding_response(), :hold)

        {:reply, :ok, state}

      {:error, :unavailable} ->
        {:reply, {:error, :unavailable}, state}
    end
  end

  @impl true

  def handle_cast({:agent_playback_started, room, command_id}, %State{owner: room} = state) do
    {:noreply, OutputSettlement.playback_started(state, command_id)}
  end

  def handle_cast(_stale, state), do: {:noreply, state}

  @impl true
  def handle_info({:vxpipe_idle_armed, owner, token, context}, %State{owner: owner} = state) do
    {:noreply, IdlePause.arm(state, token, context)}
  end

  def handle_info({:vxpipe_idle_expired, owner, token, command}, %State{owner: owner} = state) do
    {:noreply, state |> IdlePause.expire(token, command) |> start_next()}
  end

  def handle_info({:vxpipe_idle_cancelled, owner, token}, %State{owner: owner} = state) do
    {:noreply, state |> IdlePause.cancel(token) |> start_next()}
  end

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
    if state.held_output do
      held = %{state.held_output | continuation_started?: true}

      {:noreply,
       %{
         state
         | held_output: held,
           current: ActiveRequest.mark_continuation_started(state.current)
       }}
    else
      send(
        state.owner,
        {:vxpipe_capability_continuation_started, self(), continuation.command}
      )

      {:noreply, %{state | current: ActiveRequest.mark_continuation_started(state.current)}}
    end
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

        if state.held_output do
          held = Enum.reduce(segments, state.held_output, &HeldOutput.push_text(&2, &1))
          {:noreply, %{state | held_output: held}}
        else
          Enum.each(segments, &emit_text(state, &1))
          {:noreply, state}
        end

      {:error, :invalid_response} ->
        state = cancel_runtime_request(state)
        finish_or_hold(state, {:failure, :invalid_response})
    end
  end

  def handle_info(
        {:agent_runtime_event,
         %Event{kind: :context_compaction_usage, correlation: correlation, data: data}},
        %State{current: %ActiveRequest{correlation: correlation}} = state
      ) do
    {:noreply, CompactionUsage.record(state, correlation, data)}
  end

  def handle_info(
        {:agent_runtime_event, %Event{kind: :model_attempt_started, correlation: correlation}},
        %State{} = state
      ) do
    {:noreply, ModelUsage.start(state, correlation)}
  end

  def handle_info(
        {:agent_runtime_event, %Event{kind: :model_attempt_failed, correlation: correlation}},
        %State{} = state
      ) do
    {:noreply, ModelUsage.record(state, correlation, %{}, :failed)}
  end

  def handle_info(
        {:agent_runtime_event, %Event{kind: :model_usage, correlation: correlation, data: data}},
        %State{} = state
      ) do
    {:noreply, ModelUsage.record(state, correlation, data, Map.get(data, :outcome, :succeeded))}
  end

  def handle_info(
        {:agent_runtime_event, %Event{kind: kind, correlation: correlation}},
        %State{} = state
      )
      when kind in [:response_completed, :request_failed, :request_cancelled] do
    {:noreply, ModelUsage.complete(state, correlation, usage_outcome(kind))}
  end

  def handle_info({:timeout, timer, :deferred_hold_deadline}, %State{pending_literal: %{timer: timer}} = state) do
    {:noreply, state |> LiteralOutput.finish({:error, :timeout}) |> start_next()}
  end

  def handle_info({ref, verdict}, %State{pending_literal: %{task: %Task{ref: ref}}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, state |> LiteralOutput.finish(verdict) |> start_next()}
  end

  def handle_info(
        {:DOWN, ref, :process, _, _},
        %State{pending_literal: %{task: %Task{ref: ref}}} = state
      ) do
    {:noreply, state |> LiteralOutput.finish({:error, :unavailable}) |> start_next()}
  end

  def handle_info(
        {reference, verdict},
        %State{
          current: %ActiveRequest{phase: :before_turn, task: %Task{ref: reference}} = request
        } = state
      ) do
    Process.demonitor(reference, [:flush])

    case ActiveRequest.submit_checked(request, verdict, State.request_options(state)) do
      {:ok, current} -> {:noreply, %{state | current: current}}
      {:error, :unavailable} -> finish_or_hold(state, {:result, {:error, :guardrail_unavailable}})
    end
  end

  def handle_info(
        {reference, {:error, reason}},
        %State{current: %ActiveRequest{phase: :session, task: %Task{ref: reference}}} = state
      )
      when reason in [:input_revoked, :request_expired] do
    Process.demonitor(reference, [:flush])
    # Session rejected the request before admitting input or creating a history receipt.
    state = put_in(state.current.phase, :before_turn)
    failure = if reason == :request_expired, do: :provider_timeout, else: :guardrail_unavailable
    finish_or_hold(state, {:failure, failure})
  end

  def handle_info(
        {reference, result},
        %State{current: %ActiveRequest{task: %Task{ref: reference}}} = state
      ) do
    Process.demonitor(reference, [:flush])
    state = put_in(state.current.proposed_speech, OutputSettlement.proposed_speech(result))

    finish_or_hold(state, {:result, result})
  end

  def handle_info(
        {:DOWN, reference, :process, _pid, _reason},
        %State{current: %ActiveRequest{task: %Task{ref: reference}}} = state
      ) do
    finish_or_hold(state, {:failure, :provider_unavailable})
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
    if state.reply_protocol == :mode_message_v1 do
      :ok =
        Vxpipe.CallEngine.Tool.InvocationRegistry.update_source(
          state.invocation_registry,
          command.participant_id,
          command.connection_id,
          :resume
        )
    end

    case ActiveRequest.start_caller(command, State.request_options(state)) do
      {:ok, current} -> {:ok, put_current(state, current)}
      {:error, :unavailable} = error -> error
    end
  end

  defp start_next(%State{current: nil, held_output: nil, awaiting_output: nil,
                          pending_literal: %{timer: _}} = state) do
    case LiteralOutput.resume_hold(state) do
      %State{pending_literal: nil} = expired -> start_next(expired)
      checking -> checking
    end
  end

  defp start_next(%State{pending_literal: literal} = state) when not is_nil(literal), do: state

  defp start_next(
         %State{
           reply_protocol: :mode_message_v1,
           awaiting_output: pending,
           current: nil,
           held_output: nil
         } = state
       )
       when not is_nil(pending) do
    # One inference at a time, overlapping playback: while exactly one
    # predecessor output is outstanding, a leased completion may start. Caller,
    # idle and greeting work wait, as does a second overlapping completion.
    # The overlapping request's output is held until the predecessor settles.
    case start_completion(state) do
      {:ok, state} -> HeldOutput.start(state, pending)
      {:held, state} -> state
      {:empty, state} -> state
      {:error, :unavailable} -> exit(:completion_lease_unavailable)
    end
  end

  defp start_next(%State{awaiting_output: pending} = state) when not is_nil(pending), do: state
  defp start_next(%State{current: current} = state) when not is_nil(current), do: state

  defp start_next(%State{} = state) do
    case start_completion(state) do
      {:ok, state} -> state
      {:held, state} -> state
      {:empty, state} -> start_after_completions(state)
      {:error, :unavailable} -> exit(:completion_lease_unavailable)
    end
  end

  defp start_after_completions(state) do
    case IdlePause.take_timeout(state) do
      {:waiting, state} ->
        state

      {:open, state} ->
        start_next_caller(state)

      {:ready, command, state} ->
        case ActiveRequest.start_caller_idle(command, State.request_options(state)) do
          {:ok, current} ->
            put_current(state, current)

          {:error, :unavailable} ->
            send(state.owner, {:vxpipe_capability_failed, self(), command, :provider_unavailable})
            state
        end
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
      {:ok, continuation} ->
        cond do
          IdlePause.retain?(state, continuation) ->
            with {:ok, state} <- IdlePause.retain(state, continuation),
                 do: start_completion(state)

          continuation.lease.source_retired? ->
            with :ok <-
                   CompletionContinuation.retain(
                     continuation,
                     state.session,
                     state.invocation_registry
                   ),
                 do: start_completion(state)

          true ->
            start_completion_request(continuation, state)
        end

      {:error, :empty} ->
        {:empty, state}

      {:error, :held} ->
        {:held, state}

      {:error, :unavailable} = error ->
        error
    end
  end

  defp start_completion_request(continuation, state) do
    case ActiveRequest.start_completion(continuation, State.request_options(state)) do
      {:ok, current} -> {:ok, put_current(state, current)}
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
        {:ok, state} =
          LiteralOutput.start(state, command, ConversationAdmission.holding_response(), :hold)

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

  defp transition(:advance, state),
    do: {:noreply, state |> OutputSettlement.await() |> Map.put(:current, nil) |> start_next()}

  defp transition({:advance, {:completed, command, correlation}}, state) do
    history = History.record(state.history, command, correlation)

    {:noreply,
     state
     |> OutputSettlement.await()
     |> Map.put(:current, nil)
     |> Map.put(:history, history)
     |> start_next()}
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

  defp finish_or_hold(%State{held_output: %HeldOutput{} = held} = state, final) do
    {:noreply, %{state | held_output: %{held | final: final}}}
  end

  defp finish_or_hold(state, {:result, result}) do
    state.current
    |> RequestOutcome.finish(result, State.request_outcome_options(state))
    |> transition(state)
  end

  defp finish_or_hold(state, {:failure, reason}) do
    state.current
    |> RequestOutcome.fail_uncommitted(reason, State.request_outcome_options(state))
    |> transition(state)
  end

  defp put_current(state, current) do
    %{state | current: current, usage_rounds: UsageRounds.register(state.usage_rounds, current)}
  end

  defp usage_outcome(:response_completed), do: :succeeded
  defp usage_outcome(:request_failed), do: :failed
  defp usage_outcome(:request_cancelled), do: :cancelled
end
