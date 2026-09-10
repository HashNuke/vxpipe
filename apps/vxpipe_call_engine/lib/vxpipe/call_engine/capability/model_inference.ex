defmodule Vxpipe.CallEngine.Capability.ModelInference do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.Capability.SentenceAccumulator
  alias Vxpipe.CallEngine.Provider.ModelInference.Message

  @call_timeout 5_000
  @maximum_system_prompt_bytes 32_768

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :participant_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec respond(pid(), SendText.t()) :: :ok | {:error, :queue_full | :unavailable}
  def respond(capability, %SendText{} = command) do
    GenServer.call(capability, {:respond, command}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec interrupt(pid(), [{String.t(), String.t(), String.t()}]) ::
          {:ok, [SendText.t()]} | {:error, :unavailable}
  def interrupt(capability, completed_turn_ids)
      when is_pid(capability) and is_list(completed_turn_ids) do
    GenServer.call(capability, {:interrupt, completed_turn_ids}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @impl true
  def init(options) do
    state = %{
      current: nil,
      history: [],
      maximum_context_turns: Keyword.fetch!(options, :maximum_context_turns),
      maximum_output_bytes: Keyword.fetch!(options, :maximum_output_bytes),
      maximum_pending_requests: Keyword.fetch!(options, :maximum_pending_requests),
      owner: Keyword.fetch!(options, :owner),
      participant_id: Keyword.fetch!(options, :participant_id),
      pending: :queue.new(),
      provider: Keyword.fetch!(options, :provider),
      request_timeout_ms: Keyword.fetch!(options, :request_timeout_ms),
      system_prompt: Keyword.fetch!(options, :system_prompt),
      task_supervisor: Keyword.fetch!(options, :task_supervisor)
    }

    if valid_configuration?(state) do
      {:ok, state}
    else
      {:stop, :invalid_configuration}
    end
  end

  @impl true
  def handle_call({:respond, command}, _from, %{current: nil} = state) do
    case start_request(command, state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, state} -> {:reply, {:error, :unavailable}, state}
    end
  end

  def handle_call({:respond, command}, _from, state) do
    if :queue.len(state.pending) < state.maximum_pending_requests do
      pending = :queue.in(command, state.pending)
      {:reply, :ok, %{state | pending: pending}}
    else
      {:reply, {:error, :queue_full}, state}
    end
  end

  def handle_call({:interrupt, completed_turn_ids}, _from, state) do
    interrupted = interrupted_commands(state)
    state = cancel_current(state)
    discarded = MapSet.new(completed_turn_ids)

    history =
      Enum.reject(state.history, fn turn ->
        MapSet.member?(
          discarded,
          {turn.connection_id, turn.correlation_id, turn.command_id}
        )
      end)

    {:reply, {:ok, interrupted}, %{state | history: history, pending: :queue.new()}}
  end

  def handle_call(
        {:stream_chunk, request_id, chunk},
        _from,
        %{current: %{request_id: request_id}} = state
      ) do
    case SentenceAccumulator.push(state.current.accumulator, chunk) do
      {:ok, accumulator, segments} ->
        Enum.each(segments, &emit_segment(state, &1))
        current = %{state.current | accumulator: accumulator}
        {:reply, :ok, %{state | current: current}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:stream_chunk, _request_id, _chunk}, _from, state) do
    {:reply, {:error, :cancelled}, state}
  end

  def handle_call(
        {:stream_round_complete, request_id},
        _from,
        %{current: %{request_id: request_id}} = state
      ) do
    {:ok, accumulator, segments} = SentenceAccumulator.flush(state.current.accumulator)
    Enum.each(segments, &emit_segment(state, &1))
    current = %{state.current | accumulator: accumulator}
    {:reply, :ok, %{state | current: current}}
  end

  def handle_call({:stream_round_complete, _request_id}, _from, state) do
    {:reply, {:error, :cancelled}, state}
  end

  @impl true
  def handle_info({reference, result}, %{current: %{task: %{ref: reference}}} = state)
      when is_reference(reference) do
    Process.demonitor(reference, [:flush])
    state = finish_request(result, state)
    {:noreply, start_next(state)}
  end

  def handle_info(
        {:DOWN, reference, :process, _pid, _reason},
        %{current: %{task: %{ref: reference}}} = state
      ) do
    state = finish_request({:error, :provider_unavailable}, state)
    {:noreply, start_next(state)}
  end

  def handle_info(
        {:vxpipe_model_inference_timeout, reference},
        %{current: %{task: %{ref: reference}} = current} = state
      ) do
    _ = Task.shutdown(current.task, :brutal_kill)
    state = fail_current(:provider_timeout, state)
    {:noreply, start_next(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{current: %{task: task}}) do
    _ = Task.shutdown(task, :brutal_kill)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp start_request(command, state) do
    messages = request_messages(command, state)
    {provider_module, provider_config} = state.provider
    capability = self()
    request_id = make_ref()

    try do
      task =
        Task.Supervisor.async_nolink(state.task_supervisor, fn ->
          safe_request(
            provider_module,
            provider_config,
            messages,
            capability,
            request_id
          )
        end)

      timer =
        Process.send_after(
          self(),
          {:vxpipe_model_inference_timeout, task.ref},
          state.request_timeout_ms
        )

      current = %{
        accumulator: SentenceAccumulator.new(state.maximum_output_bytes),
        command: command,
        request_id: request_id,
        task: task,
        timer: timer
      }

      {:ok, %{state | current: current}}
    catch
      :exit, _reason -> {:error, state}
    end
  end

  defp finish_request({:buffered, result}, state) do
    cancel_timer(state.current.timer)

    case normalize_result(result, state.maximum_output_bytes) do
      {:ok, text} ->
        emit_segment(state, text)
        complete_current(text, state)

      {:error, reason} ->
        fail_current(reason, state)
    end
  end

  defp finish_request({:streamed, :ok}, state) do
    cancel_timer(state.current.timer)

    case SentenceAccumulator.finish(state.current.accumulator) do
      {:ok, pending, text} ->
        Enum.each(pending, &emit_segment(state, &1))
        complete_current(text, state)

      {:error, reason} ->
        fail_current(reason, state)
    end
  end

  defp finish_request({:streamed, {:error, reason}}, state),
    do: fail_current(normalize_stream_error(reason), state)

  defp finish_request({:streamed, {:tool_calls, _calls}}, state),
    do: fail_current(:invalid_response, state)

  defp finish_request(_result, state), do: fail_current(:provider_unavailable, state)

  defp complete_current(text, state) do
    send(state.owner, {:vxpipe_capability_text_complete, self(), state.current.command})

    turn = %{
      connection_id: state.current.command.connection_id,
      correlation_id: state.current.command.correlation_id,
      command_id: state.current.command.id,
      user: state.current.command.content,
      assistant: text
    }

    history = Enum.take(state.history ++ [turn], -state.maximum_context_turns)
    %{state | current: nil, history: history}
  end

  defp emit_segment(state, text) do
    send(state.owner, {:vxpipe_capability_text, self(), state.current.command, text})
  end

  defp fail_current(reason, state) do
    cancel_timer(state.current.timer)

    send(
      state.owner,
      {:vxpipe_capability_failed, self(), state.current.command, reason}
    )

    %{state | current: nil}
  end

  defp start_next(state) do
    case :queue.out(state.pending) do
      {{:value, command}, pending} ->
        state = %{state | pending: pending}

        case start_request(command, state) do
          {:ok, state} ->
            state

          {:error, state} ->
            send(state.owner, {:vxpipe_capability_failed, self(), command, :provider_unavailable})
            start_next(state)
        end

      {:empty, _pending} ->
        state
    end
  end

  defp request_messages(command, state) do
    system = %Message{role: :system, content: state.system_prompt}

    history =
      Enum.flat_map(state.history, fn turn ->
        [
          %Message{role: :user, content: turn.user},
          %Message{role: :assistant, content: turn.assistant}
        ]
      end)

    [system | history] ++ [%Message{role: :user, content: command.content}]
  end

  defp safe_request(
         provider_module,
         provider_config,
         messages,
         capability,
         request_id
       ) do
    try do
      provider_request(
        provider_module,
        provider_config,
        messages,
        capability,
        request_id
      )
    rescue
      _exception -> {:buffered, {:error, :provider_unavailable}}
    catch
      _kind, _reason -> {:buffered, {:error, :provider_unavailable}}
    end
  end

  defp provider_request(
         provider_module,
         provider_config,
         messages,
         capability,
         request_id
       ) do
    if provider_streaming?(provider_module, provider_config) do
      emit = fn chunk ->
        GenServer.call(capability, {:stream_chunk, request_id, chunk}, @call_timeout)
      end

      {:streamed, provider_module.stream(provider_config, messages, [], emit)}
    else
      {:buffered, provider_module.generate(provider_config, messages, [])}
    end
  end

  defp provider_streaming?(provider_module, provider_config) do
    Code.ensure_loaded?(provider_module) and function_exported?(provider_module, :stream, 4) and
      (not function_exported?(provider_module, :streaming?, 1) or
         provider_module.streaming?(provider_config))
  end

  defp normalize_stream_error(reason) when reason in [:invalid_response, :cancelled], do: reason
  defp normalize_stream_error(_reason), do: :provider_unavailable

  defp normalize_result({:ok, text}, maximum_output_bytes) when is_binary(text) do
    if String.valid?(text) do
      text = String.trim(text)

      if text != "" and byte_size(text) <= maximum_output_bytes do
        {:ok, text}
      else
        {:error, :invalid_response}
      end
    else
      {:error, :invalid_response}
    end
  end

  defp normalize_result({:error, _reason}, _maximum_output_bytes),
    do: {:error, :provider_unavailable}

  defp normalize_result(_result, _maximum_output_bytes), do: {:error, :invalid_response}

  defp cancel_timer(timer) do
    _ = Process.cancel_timer(timer)
    :ok
  end

  defp interrupted_commands(state) do
    current = if state.current == nil, do: [], else: [state.current.command]
    current ++ :queue.to_list(state.pending)
  end

  defp cancel_current(%{current: nil} = state), do: state

  defp cancel_current(state) do
    cancel_timer(state.current.timer)
    Process.demonitor(state.current.task.ref, [:flush])
    _ = Task.shutdown(state.current.task, :brutal_kill)
    %{state | current: nil}
  end

  defp valid_configuration?(state) do
    is_pid(state.owner) and valid_provider?(state.provider) and
      is_binary(state.system_prompt) and byte_size(state.system_prompt) > 0 and
      byte_size(state.system_prompt) <= @maximum_system_prompt_bytes and
      is_integer(state.maximum_context_turns) and state.maximum_context_turns > 0 and
      is_integer(state.maximum_pending_requests) and state.maximum_pending_requests >= 0 and
      is_integer(state.maximum_output_bytes) and state.maximum_output_bytes > 0 and
      is_integer(state.request_timeout_ms) and state.request_timeout_ms > 0
  end

  defp valid_provider?({provider_module, _provider_config}), do: is_atom(provider_module)
  defp valid_provider?(_provider), do: false
end
