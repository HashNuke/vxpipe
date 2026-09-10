defmodule Vxpipe.CallEngine.RoomAuthority.ToolCalls do
  @moduledoc false

  alias Vxpipe.CallEngine.Event.{
    ToolCallCancelled,
    ToolCallCompleted,
    ToolCallFailed,
    ToolCallStarted
  }

  alias Vxpipe.CallEngine.Id
  alias Vxpipe.CallEngine.Tool.{Call, Context}

  alias Vxpipe.CallEngine.RoomAuthority.{
    EventPublisher,
    State,
    TextCapability,
    TurnState
  }

  @spec started(State.t(), pid(), struct(), Call.t()) :: State.t()
  def started(%State{} = state, capability, %Context{} = context, %Call{} = call) do
    if invocation_authorized?(state, capability, context) and
         not Map.has_key?(state.background_tool_calls, call.id) do
      connection = Map.fetch!(state.connections, context.connection_id)

      event =
        struct!(
          ToolCallStarted,
          Map.merge(event_fields(context, call, state), %{arguments: call.arguments})
        )

      background_tool_calls =
        Map.put(state.background_tool_calls, call.id, %{
          call: call,
          capability: capability,
          command: context
        })

      state
      |> EventPublisher.publish(connection.pid, event)
      |> Map.put(:background_tool_calls, background_tool_calls)
      |> Map.update!(:next_sequence, &(&1 + 1))
    else
      state
    end
  end

  def started(%State{} = state, capability, command, %Call{} = call) do
    if authorized?(state, capability, command) do
      connection = Map.fetch!(state.connections, command.connection_id)

      event =
        struct!(
          ToolCallStarted,
          Map.merge(event_fields(command, call, state), %{arguments: call.arguments})
        )

      state
      |> EventPublisher.publish(connection.pid, event)
      |> Map.update!(:next_sequence, &(&1 + 1))
      |> TurnState.update(command, fn turn ->
        %{turn | active_tool_calls: Map.put(turn.active_tool_calls, call.id, call)}
      end)
    else
      state
    end
  end

  @spec accepted_background(State.t(), pid(), struct(), Call.t()) :: State.t()
  def accepted_background(%State{} = state, capability, command, %Call{} = call) do
    turn = TurnState.get(state, command)

    if authorized?(state, capability, command) and turn != nil and
         Map.has_key?(turn.active_tool_calls, call.id) and
         not Map.has_key?(state.background_tool_calls, call.id) do
      background_tool_calls =
        Map.put(state.background_tool_calls, call.id, %{
          call: call,
          capability: capability,
          command: command
        })

      state
      |> Map.put(:background_tool_calls, background_tool_calls)
      |> TurnState.update(command, fn turn ->
        %{turn | active_tool_calls: Map.delete(turn.active_tool_calls, call.id)}
      end)
    else
      state
    end
  end

  @spec completed(State.t(), pid(), struct(), Call.t(), term()) :: State.t()
  def completed(%State{} = state, capability, command, %Call{} = call, result) do
    stopped(state, capability, command, call, result, fn fields, value ->
      struct!(ToolCallCompleted, Map.put(fields, :result, value))
    end)
  end

  @spec failed(State.t(), pid(), struct(), Call.t(), atom()) :: State.t()
  def failed(%State{} = state, capability, command, %Call{} = call, reason) do
    stopped(state, capability, command, call, reason, fn fields, value ->
      struct!(ToolCallFailed, Map.put(fields, :reason, value))
    end)
  end

  @spec cancel_active(State.t(), map()) :: State.t()
  def cancel_active(%State{} = state, turn) do
    connection = Map.get(state.connections, turn.command.connection_id)

    if connection != nil and connection.participant_id == turn.command.participant_id do
      turn.active_tool_calls
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.reduce(state, fn call, state ->
        event = struct!(ToolCallCancelled, event_fields(turn.command, call, state))

        state
        |> EventPublisher.publish(connection.pid, event)
        |> Map.update!(:next_sequence, &(&1 + 1))
      end)
    else
      state
    end
  end

  defp stopped(state, capability, command, call, outcome, build_event) do
    case Map.pop(state.background_tool_calls, call.id) do
      {%{capability: ^capability, command: stored_command, call: stored_call}, background_calls}
      when stored_call == call ->
        state = %{state | background_tool_calls: background_calls}

        if TextCapability.current?(state, capability) and
             TurnState.key(stored_command) == TurnState.key(command) do
          background_stopped(state, stored_command, call, outcome, build_event)
        else
          state
        end

      {_missing_or_stale, _background_calls} ->
        active_stopped(state, capability, command, call, outcome, build_event)
    end
  end

  defp active_stopped(state, capability, command, call, outcome, build_event) do
    turn = TurnState.get(state, command)

    if authorized?(state, capability, command) and turn != nil and
         Map.has_key?(turn.active_tool_calls, call.id) do
      connection = Map.fetch!(state.connections, command.connection_id)
      event = build_event.(event_fields(command, call, state), outcome)

      state
      |> EventPublisher.publish(connection.pid, event)
      |> Map.update!(:next_sequence, &(&1 + 1))
      |> TurnState.update(command, fn turn ->
        %{turn | active_tool_calls: Map.delete(turn.active_tool_calls, call.id)}
      end)
    else
      state
    end
  end

  defp background_stopped(state, command, call, outcome, build_event) do
    case Map.get(state.connections, command.connection_id) do
      %{participant_id: participant_id} = connection ->
        if participant_id == source_participant_id(command) do
          event = build_event.(event_fields(command, call, state), outcome)

          state
          |> EventPublisher.publish(connection.pid, event)
          |> Map.update!(:next_sequence, &(&1 + 1))
        else
          state
        end

      _missing_connection ->
        state
    end
  end

  defp authorized?(state, capability, command) do
    connection = Map.get(state.connections, command.connection_id)

    TurnState.active?(state, command) and TextCapability.current?(state, capability) and
      connection != nil and connection.participant_id == source_participant_id(command)
  end

  defp invocation_authorized?(state, capability, context) do
    connection = Map.get(state.connections, context.connection_id)

    TextCapability.current?(state, capability) and
      state.snapshot.tenant_id == context.tenant_id and
      state.snapshot.room_id == context.room_id and
      state.snapshot.incarnation_id == context.incarnation_id and
      state.text_capability.participant_id == context.agent_participant_id and
      connection != nil and connection.participant_id == context.source_participant_id
  end

  defp event_fields(command, call, state) do
    %{
      id: Id.generate(:event),
      sequence: state.next_sequence,
      tenant_id: state.snapshot.tenant_id,
      room_id: state.snapshot.room_id,
      incarnation_id: state.snapshot.incarnation_id,
      participant_id: state.text_capability.participant_id,
      source_participant_id: source_participant_id(command),
      connection_id: command.connection_id,
      command_id: command_id(command),
      correlation_id: command.correlation_id,
      tool_call_id: call.id,
      name: call.name,
      occurred_at: DateTime.utc_now(:millisecond)
    }
  end

  defp source_participant_id(%Context{} = context), do: context.source_participant_id
  defp source_participant_id(command), do: command.participant_id

  defp command_id(%Context{} = context), do: context.command_id
  defp command_id(command), do: command.id
end
