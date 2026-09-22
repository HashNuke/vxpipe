defmodule Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.Tools do
  @moduledoc "Room-owned authorization, execution and settlement of STS tool calls."

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech, as: Capability

  alias Vxpipe.CallEngine.Event.{
    ToolCallCancelled,
    ToolCallCompleted,
    ToolCallFailed,
    ToolCallStarted
  }

  alias Vxpipe.CallEngine.Id
  alias Vxpipe.CallEngine.RoomAuthority.{EventPublisher, State}
  alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.Evidence
  alias Vxpipe.CallEngine.Tool.Context, as: ToolContext

  import Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.Evidence,
    only: [
      current?: 2,
      current_agent?: 3,
      agent_connection: 1,
      turn_key: 1,
      agent_fields: 3
    ]

  @type turn_ref :: String.t() | reference()

  @max_tool_result_bytes 65_536
  @maximum_pending 16
  @sts_tool_timeout_ms 5_000

  @spec handle_tool_call(State.t(), pid(), String.t(), reference(), turn_ref(), String.t(), map()) ::
          State.t()
  def handle_tool_call(
        %State{} = state,
        capability,
        agent_id,
        call_ref,
        provider_turn,
        name,
        arguments
      )
      when is_pid(capability) and is_binary(agent_id) and is_reference(call_ref) and
             (is_binary(provider_turn) or is_reference(provider_turn)) and is_binary(name) and
             is_map(arguments) do
    if current_agent?(state, capability, agent_id) and
         not Map.has_key?(state.sts_tool_calls, call_ref) do
      case permitted_connection(state) do
        {connection_id, connection} ->
          turn = tool_turn(state, agent_id, provider_turn, connection_id, connection)
          tool_call_id = Id.generate(:tool_attempt)

          case admit_binding(state, agent_id, name) do
            {:ok, binding} ->
              pending = %{
                agent_id: agent_id,
                turn: turn,
                source: state.speech_to_speech_capability,
                tool_call_id: tool_call_id,
                name: name,
                binding: binding
              }

              state = %{state | sts_tool_calls: Map.put(state.sts_tool_calls, call_ref, pending)}

              event =
                struct!(
                  ToolCallStarted,
                  Map.merge(agent_fields(state, connection, turn), %{
                    tool_call_id: tool_call_id,
                    name: name,
                    arguments: arguments
                  })
                )

              state = EventPublisher.publish(state, connection.pid, event)
              state = %{state | next_sequence: state.next_sequence + 1}
              maybe_execute_sts_tool(state, capability, call_ref, binding, arguments, pending)

            {:error, reason} ->
              fail_sts_tool(
                state,
                capability,
                connection,
                turn,
                {call_ref, tool_call_id},
                name,
                reason
              )
          end

        nil ->
          state
      end
    else
      state
    end
  end

  defp tool_turn(state, agent_id, provider_turn, connection_id, connection) do
    active =
      case Map.get(state.sts_turns, turn_key(provider_turn)) do
        %{agent_id: ^agent_id, connection_id: ^connection_id, connection: owner} = turn
        when owner == connection.pid ->
          turn

        _stale ->
          nil
      end

    pending_turn =
      Enum.find_value(state.sts_tool_calls, fn {_call, pending} ->
        if pending.turn.provider_turn == provider_turn and
             pending.source == state.speech_to_speech_capability,
           do: pending.turn
      end)

    active || pending_turn ||
      %{
        agent_id: agent_id,
        provider_turn: provider_turn,
        connection_id: connection_id,
        command_id: Id.generate(:command),
        correlation_id: Id.generate(:turn)
      }
  end

  defp admit_binding(state, agent_id, name) do
    if map_size(state.sts_tool_calls) >= @maximum_pending do
      {:error, :busy}
    else
      case agent_tool_binding(state, agent_id, name) do
        {:ok, binding} -> {:ok, binding}
        :error -> {:error, :unauthorized}
      end
    end
  end

  @doc """
  Delivers an externally produced result for a pending authorized STS tool call.

  Unknown or already-settled call references are ignored so late results can
  never revive fenced speech.
  """
  @spec deliver_tool_result(State.t(), pid(), reference(), term()) :: State.t()
  def deliver_tool_result(%State{} = state, capability, call_ref, result)
      when is_pid(capability) and is_reference(call_ref) do
    if current?(state, capability) do
      handle_tool_executed(state, capability, call_ref, {:ok, result})
    else
      state
    end
  end

  @spec handle_tool_executed(State.t(), pid(), reference(), {:ok, term()} | {:error, atom()}) ::
          State.t()
  def handle_tool_executed(%State{} = state, capability, call_ref, outcome)
      when is_pid(capability) and is_reference(call_ref) do
    if current?(state, capability) do
      case Map.pop(state.sts_tool_calls, call_ref) do
        {nil, _pending} ->
          state

        {pending, sts_tool_calls} ->
          state = %{state | sts_tool_calls: sts_tool_calls}
          settle_executed_tool(state, capability, pending, call_ref, outcome)
      end
    else
      state
    end
  end

  @spec handle_tool_timeout(State.t(), pid(), reference()) :: State.t()
  def handle_tool_timeout(%State{} = state, capability, call_ref)
      when is_pid(capability) and is_reference(call_ref) do
    if current?(state, capability) do
      case Map.pop(state.sts_tool_calls, call_ref) do
        {nil, _pending} ->
          state

        {pending, sts_tool_calls} ->
          state = %{state | sts_tool_calls: sts_tool_calls}
          settle_executed_tool(state, capability, pending, call_ref, {:error, :timeout})
      end
    else
      state
    end
  end

  defp agent_tool_binding(%State{participant_transfer_runtime: nil}, _agent_id, _name), do: :error

  defp agent_tool_binding(%State{} = state, agent_id, name) do
    plan = state.participant_transfer_runtime.plan
    participants = Map.get(plan, :participants) || %{}

    participants
    |> Map.values()
    |> Enum.find_value(:error, fn participant ->
      participant_id = Map.get(participant, :participant_id)
      kind = Map.get(participant, :kind)
      tools = Map.get(participant, :tools) || %{}

      if participant_id == agent_id and kind == :agent do
        case Map.fetch(tools, name) do
          {:ok, binding} -> {:ok, binding}
          :error -> :error
        end
      else
        false
      end
    end)
    |> case do
      {:ok, binding} -> scope_binding_to_activation(state, agent_id, binding)
      :error -> :error
      false -> :error
    end
  end

  defp scope_binding_to_activation(
         %State{speech_to_speech_runtime: nil} = _state,
         _agent_id,
         binding
       ),
       do: {:ok, binding}

  defp scope_binding_to_activation(%State{} = state, agent_id, binding) do
    runtime_activation = state.speech_to_speech_runtime.activation_id

    if is_nil(runtime_activation) or participant_activation(state, agent_id) == runtime_activation do
      {:ok, binding}
    else
      :error
    end
  end

  defp participant_activation(
         %State{archive_recorder: %{participant_activations: activations}},
         agent_id
       ) do
    Map.get(activations, agent_id)
  end

  defp participant_activation(_state, _agent_id), do: nil

  defp maybe_execute_sts_tool(state, capability, call_ref, binding, arguments, pending) do
    if executable_host_tool?(binding) do
      room = self()
      context = tool_context(state, pending.turn, pending.tool_call_id)
      action = Map.get(binding, :action)
      timeout = @sts_tool_timeout_ms
      _timer = Process.send_after(room, {:vxpipe_sts_tool_timeout, capability, call_ref}, timeout)

      _ =
        Task.start(fn ->
          outcome =
            try do
              apply(action, :execute, [arguments, context])
            rescue
              _exception -> {:error, :failed}
            catch
              _, _ -> {:error, :failed}
            end

          send(
            room,
            {:vxpipe_sts_tool_executed, capability, call_ref, normalize_outcome(outcome)}
          )
        end)

      state
    else
      state
    end
  end

  defp executable_host_tool?(binding) when is_map(binding) do
    action = Map.get(binding, :action)

    Map.get(binding, :type) == :host and Map.get(binding, :conversation_mode) == :blocking and
      is_atom(action) and match?({:module, _}, :code.ensure_loaded(action)) and
      function_exported?(action, :execute, 2)
  end

  defp executable_host_tool?(_binding), do: false

  defp tool_context(state, turn, tool_call_id) do
    %ToolContext{
      tenant_id: state.snapshot.tenant_id,
      room_id: state.snapshot.room_id,
      incarnation_id: state.snapshot.incarnation_id,
      agent_participant_id: turn.agent_id,
      source_participant_id: turn.agent_id,
      connection_id: turn.connection_id,
      command_id: turn.command_id,
      correlation_id: turn.correlation_id,
      tool_call_id: tool_call_id
    }
  end

  defp normalize_outcome({:ok, result}) when is_map(result), do: {:ok, result}
  defp normalize_outcome({:ok, _result}), do: {:error, :invalid_result}
  defp normalize_outcome({:error, reason}) when is_atom(reason), do: {:error, reason}
  defp normalize_outcome({:error, _reason}), do: {:error, :failed}

  defp settle_executed_tool(state, capability, pending, call_ref, outcome) do
    case pending_connection(state, pending) do
      {:ok, connection} ->
        {event, provider_result} =
          case bound_tool_result(outcome) do
            {:ok, result} ->
              event =
                struct!(
                  ToolCallCompleted,
                  Map.merge(agent_fields(state, connection, pending.turn), %{
                    tool_call_id: pending.tool_call_id,
                    name: pending.name,
                    result: result
                  })
                )

              {event, {:ok, result}}

            {:error, reason} ->
              event =
                struct!(
                  ToolCallFailed,
                  Map.merge(agent_fields(state, connection, pending.turn), %{
                    tool_call_id: pending.tool_call_id,
                    name: pending.name,
                    reason: reason
                  })
                )

              {event, {:error, reason}}
          end

        _ = deliver_provider_tool_result(capability, call_ref, provider_result)
        state = EventPublisher.publish(state, connection.pid, event)
        %{state | next_sequence: state.next_sequence + 1}

      :error ->
        state
    end
  end

  defp bound_tool_result({:ok, result}) when is_map(result) do
    try do
      if byte_size(JSON.encode!(result)) <= @max_tool_result_bytes,
        do: {:ok, result},
        else: {:error, :result_too_large}
    rescue
      _exception -> {:error, :invalid_result}
    catch
      _, _ -> {:error, :invalid_result}
    end
  end

  defp bound_tool_result({:ok, _result}), do: {:error, :invalid_result}
  defp bound_tool_result({:error, reason}) when is_atom(reason), do: {:error, reason}
  defp bound_tool_result({:error, _reason}), do: {:error, :failed}

  defp deliver_provider_tool_result(capability, call_ref, {:ok, result}) do
    try do
      Capability.send_tool_result(capability, call_ref, result)
    catch
      :exit, _reason -> {:error, :unavailable}
    end
  end

  defp deliver_provider_tool_result(capability, call_ref, {:error, _reason}) do
    try do
      Capability.send_tool_result(capability, call_ref, %{"error" => "tool_failed"})
    catch
      :exit, _reason -> {:error, :unavailable}
    end
  end

  defp fail_sts_tool(state, capability, connection, turn, {call_ref, tool_call_id}, name, reason) do
    event =
      struct!(
        ToolCallFailed,
        Map.merge(agent_fields(state, connection, turn), %{
          tool_call_id: tool_call_id,
          name: name,
          reason: reason
        })
      )

    _ = deliver_provider_tool_result(capability, call_ref, {:error, reason})
    state = EventPublisher.publish(state, connection.pid, event)
    %{state | next_sequence: state.next_sequence + 1}
  end

  @spec handle_tool_cancelled(State.t(), pid(), String.t(), reference()) :: State.t()
  def handle_tool_cancelled(%State{} = state, capability, agent_id, call_ref)
      when is_reference(call_ref) do
    if current_agent?(state, capability, agent_id) do
      case Map.pop(state.sts_tool_calls, call_ref) do
        {nil, _} ->
          state

        {pending, rest} ->
          publish_cancelled(%{state | sts_tool_calls: rest}, pending)
      end
    else
      state
    end
  end

  defp publish_cancelled(state, pending) do
    case pending_connection(state, pending) do
      {:ok, connection} ->
        event =
          struct!(
            ToolCallCancelled,
            Map.merge(agent_fields(state, connection, pending.turn), %{
              tool_call_id: pending.tool_call_id,
              name: pending.name
            })
          )

        state = EventPublisher.publish(state, connection.pid, event)
        %{state | next_sequence: state.next_sequence + 1}

      :error ->
        state
    end
  end

  defp pending_connection(state, pending) do
    with true <- pending.source == state.speech_to_speech_capability,
         {_, connection} <- permitted_connection(state),
         true <- pending_policy_current?(state, pending) do
      {:ok, connection}
    else
      _stale -> :error
    end
  end

  defp pending_policy_current?(state, %{evidence: evidence}),
    do: Evidence.tool_scope_current?(state, evidence)

  defp pending_policy_current?(_state, _pending), do: true

  defp permitted_connection(state) do
    with %{input_epoch: epoch} when is_reference(epoch) <- state.speech_to_speech_capability,
         {_, connection} = source <- agent_connection(state),
         false <- MapSet.member?(state.held_participant_ids, connection.participant_id) do
      source
    else
      _denied -> nil
    end
  end
end
