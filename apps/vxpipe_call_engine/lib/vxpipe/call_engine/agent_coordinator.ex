defmodule Vxpipe.CallEngine.AgentCoordinator do
  @moduledoc false

  use GenServer

  alias Jido.AI.Runtime.Event
  alias Vxpipe.CallEngine.AgentRequestTransformer
  alias Vxpipe.CallEngine.Capability.SentenceAccumulator
  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.Id
  alias Vxpipe.CallEngine.Tool.{Call, Context}

  @call_timeout 5_000
  @default_maximum_completed_requests 32

  def start_link(options) do
    genserver_options = Keyword.take(options, [:name])
    GenServer.start_link(__MODULE__, options, genserver_options)
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

  @spec interrupt(GenServer.server(), [{String.t(), String.t(), String.t()}]) ::
          {:ok, [SendText.t()]} | {:error, :unavailable}
  def interrupt(coordinator, completed_turn_ids) when is_list(completed_turn_ids) do
    GenServer.call(coordinator, {:interrupt, completed_turn_ids}, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @impl true
  def init(options) do
    state = %{
      agent_participant_id: Keyword.fetch!(options, :agent_participant_id),
      agent_runtime: Keyword.fetch!(options, :agent_runtime),
      agent_server: Keyword.fetch!(options, :agent_server),
      completed: [],
      current: nil,
      discarded_request_ids: [],
      maximum_completed_requests:
        Keyword.get(options, :maximum_completed_requests, @default_maximum_completed_requests),
      maximum_output_bytes: Keyword.fetch!(options, :maximum_output_bytes),
      maximum_pending_requests: Keyword.fetch!(options, :maximum_pending_requests),
      owner: Keyword.fetch!(options, :owner),
      pending: :queue.new(),
      request_options: Keyword.fetch!(options, :request_options),
      request_timeout_ms: Keyword.fetch!(options, :request_timeout_ms),
      tool_dispatcher: Keyword.fetch!(options, :tool_dispatcher)
    }

    with true <- valid_configuration?(state),
         :ok <- configure_agent(options, state) do
      {:ok, state}
    else
      _invalid -> {:stop, :invalid_configuration}
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
      {:reply, :ok, %{state | pending: :queue.in(command, state.pending)}}
    else
      {:reply, {:error, :queue_full}, state}
    end
  end

  def handle_call({:interrupt, completed_turn_ids}, _from, state) do
    interrupted = interrupted_commands(state)
    {state, _cancelled_command} = cancel_current(state, :interrupted)
    request_ids = completed_request_ids(state.completed, completed_turn_ids)
    _ = state.agent_runtime.discard_requests(state.agent_server, request_ids)
    completed = reject_completed(state.completed, completed_turn_ids)

    discarded_request_ids =
      (request_ids ++ state.discarded_request_ids)
      |> Enum.uniq()
      |> Enum.take(state.maximum_completed_requests)

    state = %{
      state
      | completed: completed,
        discarded_request_ids: discarded_request_ids,
        pending: :queue.new()
    }

    {:reply, {:ok, interrupted}, state}
  end

  @impl true
  def handle_info(
        {:jido_ai_request_event, %Event{request_id: request_id} = event},
        %{current: %{request_id: request_id}} = state
      ) do
    state = handle_runtime_event(event, state)
    {:noreply, state}
  end

  def handle_info(
        {:vxpipe_agent_request_timeout, request_id},
        %{current: %{request_id: request_id}} = state
      ) do
    {state, timed_out_command} = cancel_current(state, :provider_timeout)
    emit_failure(state.owner, self(), timed_out_command, :provider_timeout)
    {:noreply, start_next(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp handle_runtime_event(event, state) do
    if MapSet.member?(state.current.seen_event_ids, event.id) do
      state
    else
      seen_event_ids = MapSet.put(state.current.seen_event_ids, event.id)
      current = %{state.current | seen_event_ids: seen_event_ids}
      project_runtime_event(event, %{state | current: current})
    end
  end

  defp project_runtime_event(%Event{kind: :llm_delta, data: data}, state) do
    case {Map.get(data, :chunk_type), Map.get(data, :delta)} do
      {:content, delta} when is_binary(delta) -> push_text(delta, state)
      _other -> state
    end
  end

  defp project_runtime_event(%Event{kind: :tool_started} = event, state) do
    data = event.data
    call_id = event.tool_call_id || Map.get(data, :tool_call_id)
    name = event.tool_name || Map.get(data, :tool_name)
    arguments = Map.get(data, :arguments)

    if is_binary(call_id) and is_binary(name) and is_map(arguments) do
      call = %Call{id: call_id, name: name, arguments: arguments}

      send(
        state.owner,
        {:vxpipe_capability_tool_started, self(), state.current.command, call}
      )

      {pending_result, pending_tool_results} =
        Map.pop(state.current.pending_tool_results, call_id)

      current = %{
        state.current
        | pending_tool_results: pending_tool_results,
          tool_calls: Map.put(state.current.tool_calls, call_id, call)
      }

      state = %{state | current: current}

      case pending_result do
        nil -> state
        result -> complete_tool(call_id, result, state)
      end
    else
      cancel_fail_and_advance(:invalid_response, state)
    end
  end

  defp project_runtime_event(%Event{kind: :tool_completed} = event, state) do
    call_id = event.tool_call_id || Map.get(event.data, :tool_call_id)

    if is_binary(call_id) do
      complete_tool(call_id, Map.get(event.data, :result), state)
    else
      cancel_fail_and_advance(:invalid_response, state)
    end
  end

  defp project_runtime_event(%Event{kind: :request_completed, data: data}, state) do
    current = %{state.current | terminal_data: data}
    maybe_complete_terminal(%{state | current: current})
  end

  defp project_runtime_event(%Event{kind: :request_failed}, state) do
    state
    |> fail_current(:provider_unavailable)
    |> start_next()
  end

  defp project_runtime_event(%Event{kind: :request_cancelled}, state) do
    state
    |> fail_current(:provider_unavailable)
    |> start_next()
  end

  defp project_runtime_event(_event, state), do: state

  defp complete_tool(call_id, result, state) do
    case Map.pop(state.current.tool_calls, call_id) do
      {%Call{} = call, remaining} ->
        current = %{state.current | tool_calls: remaining}
        state = %{state | current: current}

        state
        |> emit_tool_result(call, result)
        |> maybe_complete_terminal()

      {nil, _remaining} ->
        pending_tool_results = Map.put(state.current.pending_tool_results, call_id, result)
        current = %{state.current | pending_tool_results: pending_tool_results}
        %{state | current: current}
    end
  end

  defp maybe_complete_terminal(%{current: nil} = state), do: state

  defp maybe_complete_terminal(state) do
    if state.current.terminal_data != nil and map_size(state.current.tool_calls) == 0 and
         map_size(state.current.pending_tool_results) == 0 do
      data = state.current.terminal_data
      request_id = state.current.request_id
      state = maybe_push_final_result(Map.get(data, :result), state)

      if current_request?(state, request_id) do
        complete_current(state)
      else
        state
      end
    else
      state
    end
  end

  defp emit_tool_result(state, call, {:ok, result, _effects}) do
    send(
      state.owner,
      {:vxpipe_capability_tool_completed, self(), state.current.command, call, result}
    )

    state
  end

  defp emit_tool_result(state, call, {:ok, result}) do
    send(
      state.owner,
      {:vxpipe_capability_tool_completed, self(), state.current.command, call, result}
    )

    state
  end

  defp emit_tool_result(state, call, _result) do
    send(
      state.owner,
      {:vxpipe_capability_tool_failed, self(), state.current.command, call, :tool_failed}
    )

    state
  end

  defp start_request(command, state) do
    request_id = Id.generate(:agent_request)
    options = request_options(command, request_id, state)

    case state.agent_runtime.ask(state.agent_server, command.content, options) do
      {:ok, ^request_id} ->
        timer =
          Process.send_after(
            self(),
            {:vxpipe_agent_request_timeout, request_id},
            state.request_timeout_ms
          )

        current = %{
          accumulator: SentenceAccumulator.new(state.maximum_output_bytes),
          command: command,
          pending_tool_results: %{},
          request_id: request_id,
          seen_event_ids: MapSet.new(),
          terminal_data: nil,
          timer: timer,
          tool_calls: %{}
        }

        {:ok, %{state | current: current}}

      _error ->
        {:error, state}
    end
  end

  defp request_options(command, request_id, state) do
    tool_context = %Context{
      tenant_id: command.tenant_id,
      room_id: command.room_id,
      incarnation_id: command.incarnation_id,
      agent_participant_id: state.agent_participant_id,
      source_participant_id: command.participant_id,
      connection_id: command.connection_id,
      command_id: command.id,
      correlation_id: command.correlation_id
    }

    existing_tool_context = Keyword.get(state.request_options, :tool_context, %{})

    state.request_options
    |> Keyword.put(:request_id, request_id)
    |> Keyword.put(:request_transformer, AgentRequestTransformer)
    |> Keyword.put(:stream_to, {:pid, self()})
    |> Keyword.put(:extra_refs, %{
      vxpipe_command_id: command.id,
      vxpipe_request_id: request_id
    })
    |> Keyword.put(
      :tool_context,
      Map.merge(existing_tool_context, %{
        vxpipe_discarded_agent_request_ids: state.discarded_request_ids,
        vxpipe_tool_context: tool_context,
        vxpipe_tool_dispatcher: state.tool_dispatcher
      })
    )
  end

  defp push_text(text, state) do
    case SentenceAccumulator.push(state.current.accumulator, text) do
      {:ok, accumulator, segments} ->
        Enum.each(segments, &emit_segment(state, &1))
        %{state | current: %{state.current | accumulator: accumulator}}

      {:error, reason} ->
        cancel_fail_and_advance(reason, state)
    end
  end

  defp maybe_push_final_result(result, state) when is_binary(result) do
    if state.current.accumulator.byte_count == 0 do
      push_text(result, state)
    else
      state
    end
  end

  defp maybe_push_final_result(_result, state), do: state

  defp complete_current(%{current: nil} = state), do: state

  defp complete_current(state) do
    cancel_timer(state.current.timer)

    case SentenceAccumulator.finish(state.current.accumulator) do
      {:ok, pending, _text} ->
        Enum.each(pending, &emit_segment(state, &1))
        send(state.owner, {:vxpipe_capability_text_complete, self(), state.current.command})

        completed =
          [
            {command_identity(state.current.command), state.current.request_id}
            | state.completed
          ]
          |> Enum.take(state.maximum_completed_requests)

        start_next(%{state | completed: completed, current: nil})

      {:error, reason} ->
        state
        |> fail_current(reason)
        |> start_next()
    end
  end

  defp fail_current(reason, state) do
    cancel_timer(state.current.timer)
    emit_failure(state.owner, self(), state.current.command, reason)
    %{state | current: nil}
  end

  defp cancel_fail_and_advance(reason, state) do
    {state, command} = cancel_current(state, reason)
    emit_failure(state.owner, self(), command, reason)
    start_next(state)
  end

  defp cancel_current(%{current: nil} = state, _reason), do: {state, nil}

  defp cancel_current(state, reason) do
    cancel_timer(state.current.timer)
    _ = state.agent_runtime.cancel(state.agent_server, state.current.request_id, reason)
    {%{state | current: nil}, state.current.command}
  end

  defp start_next(state) do
    case :queue.out(state.pending) do
      {{:value, command}, pending} ->
        state = %{state | pending: pending}

        case start_request(command, state) do
          {:ok, state} ->
            state

          {:error, state} ->
            emit_failure(state.owner, self(), command, :provider_unavailable)
            start_next(state)
        end

      {:empty, _pending} ->
        state
    end
  end

  defp interrupted_commands(state) do
    pending = :queue.to_list(state.pending)
    if state.current, do: [state.current.command | pending], else: pending
  end

  defp completed_request_ids(completed, completed_turn_ids) do
    discarded = MapSet.new(completed_turn_ids)

    for {identity, request_id} <- completed,
        MapSet.member?(discarded, identity),
        do: request_id
  end

  defp reject_completed(completed, completed_turn_ids) do
    discarded = MapSet.new(completed_turn_ids)
    Enum.reject(completed, fn {identity, _request_id} -> MapSet.member?(discarded, identity) end)
  end

  defp command_identity(command) do
    {command.connection_id, command.correlation_id, command.id}
  end

  defp current_request?(%{current: %{request_id: request_id}}, request_id), do: true
  defp current_request?(_state, _request_id), do: false

  defp emit_segment(state, text) do
    send(state.owner, {:vxpipe_capability_text, self(), state.current.command, text})
  end

  defp emit_failure(owner, coordinator, command, reason) do
    send(owner, {:vxpipe_capability_failed, coordinator, command, reason})
  end

  defp cancel_timer(timer), do: Process.cancel_timer(timer, async: true, info: false)

  defp valid_configuration?(state) do
    Code.ensure_loaded?(state.agent_runtime) and
      function_exported?(state.agent_runtime, :ask, 3) and
      function_exported?(state.agent_runtime, :cancel, 3) and
      function_exported?(state.agent_runtime, :discard_requests, 2) and
      is_pid(state.owner) and
      valid_server?(state.agent_server) and
      valid_server?(state.tool_dispatcher) and
      is_integer(state.maximum_completed_requests) and state.maximum_completed_requests > 0 and
      is_integer(state.maximum_output_bytes) and state.maximum_output_bytes > 0 and
      is_integer(state.maximum_pending_requests) and state.maximum_pending_requests >= 0 and
      is_list(state.request_options) and
      is_map(Keyword.get(state.request_options, :tool_context, %{})) and
      is_integer(state.request_timeout_ms) and state.request_timeout_ms > 0
  end

  defp valid_server?(server) do
    is_pid(GenServer.whereis(server))
  rescue
    _exception -> false
  end

  defp configure_agent(options, state) do
    case Keyword.fetch(options, :agent_configuration) do
      :error ->
        :ok

      {:ok, configuration} when is_list(configuration) ->
        Vxpipe.CallEngine.AgentFactory.configure(state.agent_server, configuration)

      {:ok, _invalid} ->
        {:error, :invalid_configuration}
    end
  end
end
