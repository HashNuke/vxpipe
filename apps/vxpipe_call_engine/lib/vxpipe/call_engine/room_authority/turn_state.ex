defmodule Vxpipe.CallEngine.RoomAuthority.TurnState do
  @moduledoc false

  alias Vxpipe.CallEngine.Command.{ContinueAgent, SendText}
  alias Vxpipe.CallEngine.RoomAuthority.State
  alias Vxpipe.CallEngine.TextToSpeechRequest

  @spec put(State.t(), SendText.t() | ContinueAgent.t()) :: State.t()
  def put(%State{} = state, command) do
    turn = %{
      active_tool_calls: %{},
      command: command,
      generation_complete?: false,
      order: state.next_sequence,
      pending_speech: 0
    }

    %{state | agent_turns: Map.put(state.agent_turns, key(command), turn)}
  end

  @spec get(State.t(), struct()) :: map() | nil
  def get(%State{} = state, command), do: Map.get(state.agent_turns, key(command))

  @spec update(State.t(), struct(), (map() -> map())) :: State.t()
  def update(%State{} = state, command, update) when is_function(update, 1) do
    case Map.fetch(state.agent_turns, key(command)) do
      {:ok, turn} -> replace(state, command, update.(turn))
      :error -> state
    end
  end

  @spec replace(State.t(), struct(), map()) :: State.t()
  def replace(%State{} = state, command, turn) do
    %{state | agent_turns: Map.put(state.agent_turns, key(command), turn)}
  end

  @spec delete(State.t(), struct()) :: State.t()
  def delete(%State{} = state, command) do
    %{state | agent_turns: Map.delete(state.agent_turns, key(command))}
  end

  @spec active?(State.t(), struct()) :: boolean()
  def active?(%State{} = state, command) do
    case get(state, command) do
      %{command: active} -> active.id == command_id(command)
      nil -> false
    end
  end

  @spec key(struct()) :: {String.t(), String.t(), String.t()}
  def key(command) do
    {command.connection_id, command.correlation_id, command_id(command)}
  end

  defp command_id(%SendText{} = command), do: command.id
  defp command_id(%ContinueAgent{} = command), do: command.id
  defp command_id(%TextToSpeechRequest{} = request), do: request.command_id
end
