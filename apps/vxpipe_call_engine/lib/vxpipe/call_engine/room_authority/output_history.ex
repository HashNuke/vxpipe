defmodule Vxpipe.CallEngine.RoomAuthority.OutputHistory do
  @moduledoc false

  alias Vxpipe.CallEngine.AgentRuntime.Coordinator
  alias Vxpipe.CallEngine.RoomAuthority.{CallerAnswer, FirstMessage, State, TurnState}

  @spec confirm(State.t(), struct(), String.t(), String.t()) :: State.t()
  def confirm(%State{} = state, command, output_id, text) do
    case TurnState.get(state, command) do
      nil ->
        state

      turn ->
        segments = Map.get(turn, :supported_segments, [])

        if Enum.any?(segments, fn {id, _text} -> id == output_id end) do
          state
        else
          state =
            TurnState.replace(
              state,
              command,
              Map.put(turn, :supported_segments, segments ++ [{output_id, text}])
            )

          if TurnState.output_eligible?(state, command),
            do: CallerAnswer.delivered(state, command, text),
            else: state
        end
    end
  end

  @spec settle(State.t(), struct()) :: :ok | :ignored
  def settle(%State{text_capability: %{module: Coordinator} = capability} = state, command) do
    turn = TurnState.get(state, command)

    if turn do
      segments = Map.get(turn, :supported_segments, [])
      text = if segments == [], do: nil, else: Enum.map_join(segments, " ", &elem(&1, 1))

      case Coordinator.settle_output(capability.pid, turn.command, text) do
        result when result in [:ok, :ignored] -> result
        {:error, :unavailable} -> exit(:output_history_unavailable)
      end
    else
      :ignored
    end
  end

  def settle(%State{}, _command), do: :ignored

  @spec settle_untracked(State.t(), struct()) :: :ok | :ignored
  def settle_untracked(
        %State{text_capability: %{module: Coordinator} = capability} = state,
        command
      ) do
    if command.tenant_id == state.snapshot.tenant_id and command.room_id == state.snapshot.room_id and
         command.incarnation_id == state.snapshot.incarnation_id do
      # A private continuation can complete with no source connection and no
      # public output turn. It still closes its exact coordinator history gate.
      case Coordinator.settle_output(capability.pid, command, nil) do
        result when result in [:ok, :ignored] -> result
        {:error, :unavailable} -> exit(:output_history_unavailable)
      end
    else
      :ignored
    end
  end

  def settle_untracked(%State{}, _command), do: :ignored

  @spec detached(State.t(), String.t()) :: State.t()
  def detached(%State{} = state, connection_id) do
    state.agent_turns
    |> Map.values()
    |> Enum.filter(&(&1.command.connection_id == connection_id))
    |> Enum.reduce(state, fn turn, current ->
      case settle(current, turn.command) do
        :ok -> current |> TurnState.delete(turn.command) |> FirstMessage.complete(turn.command)
        :ignored -> current
      end
    end)
  end
end
