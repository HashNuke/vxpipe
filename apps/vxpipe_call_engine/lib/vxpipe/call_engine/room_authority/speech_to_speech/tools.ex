defmodule Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.Tools do
  @moduledoc "Room-owned authorization, execution and settlement of STS tool calls."

  alias Vxpipe.AgentRuntime.ToolRegistry
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech, as: Capability
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.ToolCompletions
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.Tree

  alias Vxpipe.CallEngine.Event.{
    ToolCallCancelled,
    ToolCallCompleted,
    ToolCallFailed,
    ToolCallStarted
  }

  alias Vxpipe.CallEngine.Id
  alias Vxpipe.CallEngine.SpeechToSpeechRuntime
  alias Vxpipe.CallEngine.RoomAuthority.{EventPublisher, State}
  alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.Evidence
  alias Vxpipe.CallEngine.Tool.Context, as: ToolContext

  alias Vxpipe.CallEngine.Tool.{
    CompletionLease,
    InvocationRegistry,
    PlatformResult
  }

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

          case admit_binding(state, agent_id, name, arguments) do
            {:ok, binding} ->
              pending = %{
                agent_id: agent_id,
                turn: turn,
                source: state.speech_to_speech_capability,
                tool_call_id: tool_call_id,
                name: name,
                binding: binding,
                context: tool_context(state, turn, tool_call_id, capability, connection)
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

  defp admit_binding(state, agent_id, name, arguments) do
    if map_size(state.sts_tool_calls) >= @maximum_pending do
      {:error, :busy}
    else
      agent_tool_binding(state, agent_id, name, arguments)
    end
  end

  @spec handle_tool_executed(State.t(), pid(), reference(), {:ok, term()} | {:error, atom()}) ::
          State.t()
  def handle_tool_executed(%State{} = state, capability, call_ref, outcome)
      when is_pid(capability) and is_reference(call_ref) do
    if current?(state, capability) do
      case Map.fetch(state.sts_tool_calls, call_ref) do
        :error ->
          state

        {:ok, pending} ->
          settle_executed_tool(state, capability, pending, call_ref, outcome)
      end
    else
      state
    end
  end

  defp agent_tool_binding(%State{} = state, agent_id, name, arguments) do
    with %SpeechToSpeechRuntime{
           participant_id: ^agent_id,
           activation_id: activation,
           tool_registry: %ToolRegistry{} = registry
         } <- state.speech_to_speech_runtime,
         true <- is_binary(activation) and participant_activation(state, agent_id) == activation,
         true <- state.speech_to_speech_capability.activation_id == activation,
         {:ok, descriptor} <- ToolRegistry.resolve(registry, name, arguments) do
      {:ok, descriptor.binding}
    else
      {:error, :invalid_arguments} -> {:error, :invalid_arguments}
      _unavailable -> {:error, :unauthorized}
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
    case InvocationRegistry.submit(
           Tree.invocation_registry(capability),
           binding,
           arguments,
           pending.context,
           pending.tool_call_id
         ) do
      {:accepted, mode} ->
        case Capability.admit_tool(capability, call_ref, mode) do
          :ok -> state
          {:error, _reason} -> exit(:tool_admission_unavailable)
        end

      {:error, reason} ->
        handle_tool_executed(state, capability, call_ref, {:error, reason})
    end
  end

  def handle_completion(
        %State{speech_to_speech_capability: %{pid: capability}} = state,
        bridge,
        %CompletionLease{} = lease
      ) do
    if Tree.tool_completions(capability) == bridge do
      case Enum.find(state.sts_tool_calls, fn {_ref, pending} ->
             pending.tool_call_id == lease.invocation_id
           end) do
        {call_ref, _pending} ->
          state = handle_tool_executed(state, capability, call_ref, lease.completion.outcome)

          acknowledge_settled(state, bridge, lease, call_ref)

        nil ->
          state
      end
    else
      state
    end
  end

  def handle_completion(state, _bridge, _lease), do: state

  defp acknowledge_settled(state, bridge, lease, call_ref) do
    if Map.has_key?(state.sts_tool_calls, call_ref) do
      state
    else
      case ToolCompletions.acknowledge(bridge, lease) do
        :ok -> finish_admission(state, lease, call_ref)
        {:error, _reason} -> exit(:tool_completion_unavailable)
      end
    end
  end

  defp finish_admission(
         state,
         %{
           completion: %{outcome: {:ok, %PlatformResult{effect: :participant_transfer_committed}}}
         },
         _call
       ),
       do: state

  defp finish_admission(state, _lease, call) do
    case Capability.finish_tool(state.speech_to_speech_capability.pid, call) do
      :ok -> state
      {:error, _reason} -> exit(:tool_completion_unavailable)
    end
  end

  defp tool_context(state, turn, tool_call_id, capability, connection) do
    %ToolContext{
      tenant_id: state.snapshot.tenant_id,
      room_id: state.snapshot.room_id,
      incarnation_id: state.snapshot.incarnation_id,
      agent_participant_id: turn.agent_id,
      source_participant_id: connection.participant_id,
      connection_id: turn.connection_id,
      command_id: turn.command_id,
      correlation_id: turn.correlation_id,
      tool_call_id: tool_call_id,
      source_capability: capability
    }
  end

  defp settle_executed_tool(
         state,
         capability,
         pending,
         call_ref,
         {:ok, %PlatformResult{effect: :participant_transfer_committed}}
       ) do
    send(
      self(),
      {:vxpipe_platform_effect, capability, pending.context, :participant_transfer_committed}
    )

    %{state | sts_tool_calls: Map.delete(state.sts_tool_calls, call_ref)}
  end

  defp settle_executed_tool(
         _state,
         _capability,
         %{delivery_unavailable?: true},
         _call_ref,
         _outcome
       ),
       do: exit(:tool_result_unavailable)

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

        case deliver_provider_tool_result(capability, call_ref, provider_result) do
          :ok -> :ok
          {:error, _reason} -> exit(:tool_result_unavailable)
        end

        state = EventPublisher.publish(state, connection.pid, event)
        queue_platform_effect(capability, pending, outcome, provider_result)

        %{
          state
          | next_sequence: state.next_sequence + 1,
            sts_tool_calls: Map.delete(state.sts_tool_calls, call_ref)
        }

      :error ->
        state
    end
  end

  @doc false
  def platform_effect_current?(state, capability, scope) do
    current?(state, capability) and pending_source_current?(state, scope) and
      permitted_connection(state) != nil and
      Evidence.tool_scope_current?(state, scope.evidence)
  end

  defp queue_platform_effect(
         capability,
         pending,
         {:ok, %PlatformResult{effect: :hangup}},
         {:ok, _result}
       ) do
    scope = Map.take(pending, [:source, :evidence, :context])
    send(self(), {:vxpipe_sts_platform_effect, capability, scope, :hangup})
  end

  defp queue_platform_effect(_capability, _pending, _outcome, _result), do: :ok

  defp bound_tool_result({:ok, %PlatformResult{result: result}}),
    do: bound_tool_result({:ok, result})

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

  defp deliver_provider_tool_result(capability, call_ref, {:error, :unknown}) do
    deliver_provider_tool_result(capability, call_ref, {:ok, %{"status" => "unknown"}})
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

    case deliver_provider_tool_result(capability, call_ref, {:error, reason}) do
      :ok -> :ok
      {:error, _reason} -> exit(:tool_result_unavailable)
    end

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
    with true <- pending_source_current?(state, pending),
         {_, connection} <- pending_source_connection(state),
         true <- pending_policy_current?(state, pending) do
      {:ok, connection}
    else
      _stale -> :error
    end
  end

  defp pending_source_current?(%{speech_to_speech_capability: current}, %{
         source: source
       }) do
    Map.take(source, [
      :pid,
      :participant_id,
      :activation_id,
      :connection_id,
      :connection,
      :input_handle
    ]) ==
      Map.take(current, [
        :pid,
        :participant_id,
        :activation_id,
        :connection_id,
        :connection,
        :input_handle
      ])
  end

  defp pending_source_connection(state), do: agent_connection(state)

  defp pending_policy_current?(state, %{evidence: evidence}),
    do: Evidence.pending_tool_scope_current?(state, evidence)

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
