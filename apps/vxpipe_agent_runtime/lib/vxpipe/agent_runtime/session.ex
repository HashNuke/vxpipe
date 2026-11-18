defmodule Vxpipe.AgentRuntime.Session do
  @moduledoc "A supervised, single-request agent conversation boundary."

  use GenServer

  alias Vxpipe.AgentRuntime.{
    Conversation,
    Event,
    Input,
    Message,
    Readiness,
    Request,
    RequestRunner,
    Result,
    SessionConfiguration
  }

  @derive {Inspect, only: [:status]}
  defstruct [
    :configuration,
    :readiness,
    :conversation,
    :active_task,
    :active_token,
    :caller,
    :correlation,
    :request_timer,
    :termination_reason,
    pending_output: nil,
    pending_replay: nil,
    status: :idle,
    submission_phase: :idle,
    cancel_callers: []
  ]

  @type server :: GenServer.server()
  @maximum_recorded_assistant_bytes 64 * 1_024

  @doc "Pins compactor instructions and reply recovery policy into the restartable child specification."
  def child_spec(options) do
    case SessionConfiguration.pin_compaction(options) do
      {:ok, pinned} -> super(pinned)
      {:error, _reason} -> raise ArgumentError, "invalid agent session compaction configuration"
    end
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) when is_list(options) do
    genserver_options = Keyword.take(options, [:name])
    session_options = Keyword.delete(options, :name)
    GenServer.start_link(__MODULE__, session_options, genserver_options)
  end

  @spec request(server(), String.t() | Input.t(), map(), timeout()) ::
          {:ok, Result.t()} | {:error, atom()}
  def request(server, input, correlation, timeout \\ :infinity) do
    GenServer.call(server, {:request, :caller, input, correlation}, timeout)
  end

  @spec continue(server(), String.t() | Input.t(), map(), timeout()) ::
          {:ok, Result.t()} | {:error, atom()}
  def continue(server, input, correlation, timeout \\ :infinity) do
    GenServer.call(server, {:request, :engine, input, correlation}, timeout)
  end

  @doc """
  Retains a trusted engine observation without starting model generation.

  A nonempty durable correlation makes repeated delivery idempotent. Existing
  observations remain unchanged. Generation and pending host settlement must
  finish before another observation can be retained.
  """
  @spec record_engine(server(), String.t() | Input.t(), map(), timeout()) ::
          :ok | {:error, atom()}
  def record_engine(server, input, correlation, timeout \\ 5_000)

  def record_engine(server, input, correlation, timeout)
      when is_map(correlation) and map_size(correlation) > 0 do
    GenServer.call(server, {:record_engine, input, correlation}, timeout)
  end

  def record_engine(_server, _input, _correlation, _timeout),
    do: {:error, :invalid_correlation}

  @spec record_assistant(server(), String.t(), map(), timeout()) ::
          :ok | {:error, :busy | :invalid_message}
  def record_assistant(server, text, correlation, timeout \\ 5_000)

  def record_assistant(server, text, correlation, timeout)
      when is_binary(text) and is_map(correlation) do
    GenServer.call(server, {:record_assistant, text, correlation}, timeout)
  end

  def record_assistant(_server, _text, _correlation, _timeout),
    do: {:error, :invalid_message}

  @doc """
  Closes the outstanding host-settled output before the next model request.

  Supply a spoken_assistant message containing only supported delivered text,
  or nil when delivery is known zero or unknown. The host retains that evidence;
  no playback diagnostics enter conversation history. Late/duplicate settlements
  cannot append or rewrite history.
  """
  @spec settle_output(server(), map(), Message.t() | nil, timeout()) ::
          :ok | {:error, :busy | :stale_settlement | :invalid_message}
  def settle_output(server, correlation, message, timeout \\ 5_000)
      when is_map(correlation) do
    GenServer.call(server, {:settle_output, correlation, message}, timeout)
  end

  @spec status(server()) :: :idle | :busy
  def status(server), do: GenServer.call(server, :status)

  @spec readiness(server()) ::
          {:ok, Readiness.t(), Readiness.status()} | {:error, :unavailable}
  def readiness(server) do
    GenServer.call(server, :readiness, 1_000)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec cancel(server(), timeout()) :: :ok | {:error, :idle}
  def cancel(server, timeout \\ 5_000), do: GenServer.call(server, :cancel, timeout)

  @spec discard(server(), [map()], timeout()) ::
          :ok | {:error, :busy | :invalid_correlations}
  def discard(server, correlations, timeout \\ 5_000)

  def discard(server, correlations, timeout) when is_list(correlations) do
    if Enum.all?(correlations, &is_map/1) do
      GenServer.call(server, {:discard, correlations}, timeout)
    else
      {:error, :invalid_correlations}
    end
  end

  def discard(_server, _correlations, _timeout), do: {:error, :invalid_correlations}

  @spec durable?(server(), map(), timeout()) ::
          {:ok, boolean()} | {:error, :busy | :invalid_correlation}
  def durable?(server, correlation, timeout \\ 5_000)

  def durable?(server, correlation, timeout) when is_map(correlation) do
    GenServer.call(server, {:durable?, correlation}, timeout)
  end

  def durable?(_server, _correlation, _timeout), do: {:error, :invalid_correlation}

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)

    with {:ok, configuration} <- SessionConfiguration.new(options) do
      {:ok,
       %__MODULE__{
         configuration: configuration,
         readiness: Readiness.new(configuration),
         conversation:
           Conversation.new(configuration.instructions, configuration.initial_messages)
       }}
    else
      _invalid -> {:stop, :invalid_configuration}
    end
  end

  @impl true
  def handle_call(
        {:request, origin, input, correlation},
        caller,
        %{status: :idle, pending_output: nil} = state
      ) do
    with {:ok, request} <- Request.new(input, correlation, origin: origin) do
      state = admit_input(state, request)
      emit(state.configuration.event_destination, Event.new(:request_started, correlation))
      session = self()
      token = make_ref()

      begin_submission = fn ->
        begin_submission(session, token, state.configuration.commit_timeout_ms)
      end

      commit = fn conversation ->
        commit_conversation(session, token, conversation, state.configuration.commit_timeout_ms)
      end

      emit_text_delta = fn text ->
        emit_request_event(
          session,
          token,
          :text_delta,
          %{text: text},
          state.configuration.event_handoff_timeout_ms
        )
      end

      emit_model_usage = fn usage, provider_metadata ->
        emit_request_event(
          session,
          token,
          :model_usage,
          %{usage: usage, provider_metadata: provider_metadata},
          state.configuration.event_handoff_timeout_ms
        )
      end

      emit_model_attempt_started = fn ->
        emit_request_event(
          session,
          token,
          :model_attempt_started,
          %{},
          state.configuration.event_handoff_timeout_ms
        )
      end

      emit_context_compaction_usage = fn usage, provider_metadata, outcome ->
        emit_request_event(
          session,
          token,
          :context_compaction_usage,
          %{usage: usage, provider_metadata: provider_metadata, outcome: outcome},
          state.configuration.event_handoff_timeout_ms
        )
      end

      callbacks = %{
        begin_submission: begin_submission,
        commit: commit,
        emit_context_compaction_usage: emit_context_compaction_usage,
        emit_model_attempt_started: emit_model_attempt_started,
        emit_model_usage: emit_model_usage,
        emit_text_delta: emit_text_delta
      }

      runner_options = SessionConfiguration.runner_options(state.configuration, callbacks)

      task =
        Task.Supervisor.async(Vxpipe.AgentRuntime.RequestSupervisor, fn ->
          RequestRunner.run(state.conversation, request, runner_options)
        end)

      request_timer =
        Process.send_after(
          self(),
          {:agent_runtime_request_timeout, token},
          state.configuration.request_timeout_ms
        )

      {:noreply,
       %{
         state
         | status: :busy,
           active_task: task,
           active_token: token,
           caller: caller,
           correlation: correlation,
           request_timer: request_timer
       }}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:request, _origin, _input, _correlation}, _caller, state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call(
        {:record_engine, input, correlation},
        _caller,
        %{status: :idle, pending_output: nil} = state
      )
      when is_map(correlation) and map_size(correlation) > 0 do
    with {:ok, request} <- Request.new(input, correlation, origin: :engine),
         true <- String.valid?(request.input) and String.trim(request.input) != "" do
      conversation =
        if Conversation.durable?(state.conversation, correlation) do
          state.conversation
        else
          Conversation.append_exchange(
            state.conversation,
            [Message.user(request.input, :engine)],
            correlation,
            :durable
          )
        end

      {:reply, :ok, %{state | conversation: conversation}}
    else
      false -> {:reply, {:error, :invalid_input}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:record_engine, _input, _correlation}, _caller, state),
    do: {:reply, {:error, :busy}, state}

  def handle_call(
        {:record_assistant, text, correlation},
        _caller,
        %{status: :idle, pending_output: nil} = state
      ) do
    if valid_assistant_message?(text) do
      if state.configuration.history_mode == :host_settled do
        {:reply, :ok, %{state | pending_output: correlation, pending_replay: nil}}
      else
        conversation =
          Conversation.append_exchange(
            state.conversation,
            [Message.assistant(text, [])],
            correlation,
            :discardable
          )

        {:reply, :ok, %{state | conversation: conversation}}
      end
    else
      {:reply, {:error, :invalid_message}, state}
    end
  end

  def handle_call({:record_assistant, _text, _correlation}, _caller, state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call(
        {:settle_output, correlation, message},
        _caller,
        %{status: :idle, pending_output: correlation} = state
      )
      when is_map(correlation) do
    if valid_settled_message?(message, state.configuration.maximum_output_bytes) do
      message = Vxpipe.AgentRuntime.PendingReplyReplay.settle(state.pending_replay, message)

      conversation =
        if message == nil,
          do: state.conversation,
          else: Conversation.append_exchange(state.conversation, [message], correlation, :durable)

      {:reply, :ok,
       %{state | conversation: conversation, pending_output: nil, pending_replay: nil}}
    else
      {:reply, {:error, :invalid_message}, state}
    end
  end

  def handle_call({:settle_output, _correlation, _message}, _caller, %{status: :busy} = state),
    do: {:reply, {:error, :busy}, state}

  def handle_call({:settle_output, _correlation, _message}, _caller, state),
    do: {:reply, {:error, :stale_settlement}, state}

  def handle_call(:status, _caller, state), do: {:reply, state.status, state}

  def handle_call(:readiness, _caller, state) do
    status = Readiness.status(state.configuration, state.status)
    {:reply, {:ok, state.readiness, status}, state}
  end

  def handle_call({:durable?, correlation}, _caller, %{status: :idle} = state) do
    {:reply, {:ok, Conversation.durable?(state.conversation, correlation)}, state}
  end

  def handle_call({:durable?, _correlation}, _caller, state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call({:discard, correlations}, _caller, %{status: :idle} = state) do
    conversation = Conversation.discard(state.conversation, correlations)
    {:reply, :ok, %{state | conversation: conversation}}
  end

  def handle_call({:discard, _correlations}, _caller, state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call(:cancel, _caller, %{status: :idle} = state),
    do: {:reply, {:error, :idle}, state}

  def handle_call(:cancel, caller, %{submission_phase: :submitting} = state) do
    {:noreply,
     %{
       state
       | termination_reason: state.termination_reason || :cancelled,
         cancel_callers: [caller | state.cancel_callers]
     }}
  end

  def handle_call(:cancel, _caller, state) do
    {:reply, :ok, terminate_active_request(state, :cancelled)}
  end

  @impl true
  def handle_info(
        {:agent_runtime_request_event, worker, token, event_ref, kind, data},
        %{active_task: %{pid: worker}, active_token: token} = state
      )
      when kind in [
             :context_compaction_usage,
             :model_attempt_started,
             :text_delta,
             :model_usage
           ] and is_map(data) do
    emit(state.configuration.event_destination, Event.new(kind, state.correlation, data))

    send(worker, {:agent_runtime_request_event_emitted, token, event_ref})
    {:noreply, state}
  end

  def handle_info(
        {:agent_runtime_begin_submission, worker, token},
        %{active_task: %{pid: worker}, active_token: token, submission_phase: :idle} = state
      ) do
    send(worker, {:agent_runtime_submission_begun, token})
    {:noreply, %{state | submission_phase: :submitting}}
  end

  def handle_info(
        {:agent_runtime_commit, worker, token, %Conversation{} = conversation},
        %{active_task: %{pid: worker}, active_token: token} = state
      ) do
    state = %{state | conversation: conversation, submission_phase: :idle}

    case state.termination_reason do
      nil ->
        send(worker, {:agent_runtime_committed, token})
        {:noreply, state}

      reason ->
        {:noreply, terminate_active_request(state, reason)}
    end
  end

  def handle_info(
        {:agent_runtime_request_timeout, token},
        %{active_token: token, submission_phase: :submitting} = state
      ) do
    {:noreply,
     %{
       state
       | request_timer: nil,
         termination_reason: state.termination_reason || :request_timeout
     }}
  end

  def handle_info({:agent_runtime_request_timeout, token}, %{active_token: token} = state) do
    {:noreply, terminate_active_request(%{state | request_timer: nil}, :request_timeout)}
  end

  def handle_info({reference, run_result}, %{active_task: %{ref: reference}} = state) do
    Process.demonitor(reference, [:flush])
    {reply, event, state} = normalize_result(run_result, state.correlation, state)
    emit(state.configuration.event_destination, event)
    GenServer.reply(state.caller, reply)
    {:noreply, clear_request(state)}
  end

  def handle_info(
        {:DOWN, reference, :process, _pid, _reason},
        %{active_task: %{ref: reference}} = state
      ) do
    if is_nil(state.termination_reason) do
      result = Result.failed(:provider_unavailable, state.correlation)

      emit(
        state.configuration.event_destination,
        Event.new(:request_failed, state.correlation)
      )

      GenServer.reply(state.caller, {:ok, result})
      {:noreply, clear_request(state)}
    else
      {:noreply, complete_termination(state, state.termination_reason)}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp normalize_result(
         {:ok, output, %Conversation{} = conversation,
          %Vxpipe.AgentRuntime.PendingReplyReplay{} = pending},
         correlation,
         state
       ) do
    {reply, event, state} = normalize_result({:ok, output, conversation}, correlation, state)
    {reply, event, %{state | pending_replay: pending}}
  end

  defp normalize_result({:ok, output, %Conversation{} = conversation}, correlation, state)
       when is_binary(output) or is_struct(output, Vxpipe.AgentRuntime.Dialogue) do
    result = Result.completed(output, correlation)

    {{:ok, result}, Event.new(:response_completed, correlation),
     %{state | conversation: conversation}}
  end

  defp normalize_result({:error, reason}, correlation, state) when is_atom(reason) do
    result = Result.failed(reason, correlation)
    {{:ok, result}, Event.new(:request_failed, correlation), state}
  end

  defp normalize_result(_invalid, correlation, state) do
    result = Result.failed(:invalid_provider_response, correlation)
    {{:ok, result}, Event.new(:request_failed, correlation), state}
  end

  defp valid_assistant_message?(text) do
    String.valid?(text) and String.trim(text) != "" and
      byte_size(text) <= @maximum_recorded_assistant_bytes
  end

  defp valid_settled_message?(nil, _maximum), do: true

  defp valid_settled_message?(message, maximum), do: Message.valid_spoken?(message, maximum)

  defp admit_input(%{configuration: %{history_mode: :host_settled}} = state, request) do
    conversation =
      Conversation.append_exchange(
        state.conversation,
        [Message.user(request.input, request.origin)],
        request.correlation,
        :durable
      )

    %{
      state
      | conversation: conversation,
        pending_output: request.correlation,
        pending_replay: nil
    }
  end

  defp admit_input(state, _request), do: state

  defp clear_request(state) do
    state = cancel_request_timer(state)

    %{
      state
      | status: :idle,
        active_task: nil,
        active_token: nil,
        caller: nil,
        correlation: nil,
        request_timer: nil,
        termination_reason: nil,
        submission_phase: :idle,
        cancel_callers: []
    }
  end

  defp begin_submission(session, token, timeout_ms) do
    send(session, {:agent_runtime_begin_submission, self(), token})

    receive do
      {:agent_runtime_submission_begun, ^token} -> :ok
    after
      timeout_ms -> {:error, :commit_unavailable}
    end
  end

  defp commit_conversation(session, token, conversation, timeout_ms) do
    send(session, {:agent_runtime_commit, self(), token, conversation})

    receive do
      {:agent_runtime_committed, ^token} -> :ok
    after
      timeout_ms -> {:error, :commit_unavailable}
    end
  end

  defp emit_request_event(session, token, kind, data, timeout_ms) do
    event_ref = make_ref()
    send(session, {:agent_runtime_request_event, self(), token, event_ref, kind, data})

    receive do
      {:agent_runtime_request_event_emitted, ^token, ^event_ref} -> :ok
    after
      timeout_ms -> {:error, :event_unavailable}
    end
  end

  defp terminate_active_request(state, reason) do
    _ = Task.shutdown(state.active_task, :brutal_kill)
    Process.demonitor(state.active_task.ref, [:flush])

    complete_termination(state, reason)
  end

  defp complete_termination(state, :cancelled) do
    result = Result.cancelled(state.correlation)
    emit_cancelled(state)
    GenServer.reply(state.caller, {:ok, result})
    reply_cancel_callers(state.cancel_callers)
    clear_request(state)
  end

  defp complete_termination(state, :request_timeout) do
    result = Result.failed(:request_timeout, state.correlation)

    emit(
      state.configuration.event_destination,
      Event.new(:request_failed, state.correlation)
    )

    GenServer.reply(state.caller, {:ok, result})
    reply_cancel_callers(state.cancel_callers)
    clear_request(state)
  end

  defp emit_cancelled(state) do
    emit(
      state.configuration.event_destination,
      Event.new(:request_cancelled, state.correlation)
    )
  end

  defp reply_cancel_callers(callers) do
    Enum.each(callers, &GenServer.reply(&1, :ok))
  end

  defp cancel_request_timer(%{request_timer: nil} = state), do: state

  defp cancel_request_timer(state) do
    _ = Process.cancel_timer(state.request_timer)
    %{state | request_timer: nil}
  end

  defp emit(destination, event), do: send(destination, {:agent_runtime_event, event})
end
