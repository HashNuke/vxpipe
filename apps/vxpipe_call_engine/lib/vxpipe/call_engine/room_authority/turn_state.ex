defmodule Vxpipe.CallEngine.RoomAuthority.TurnState do
  @moduledoc false

  alias Vxpipe.CallEngine.Command.{ContinueAgent, SendText}
  alias Vxpipe.CallEngine.RoomAuthority.State
  alias Vxpipe.CallEngine.TextToSpeechRequest
  alias Vxpipe.CallEngine.Tool.Context

  @spec put(State.t(), SendText.t() | ContinueAgent.t()) :: State.t()
  def put(%State{} = state, command, observation \\ nil) do
    turn = %{
      diagnostic_response: Vxpipe.CallEngine.Diagnostics.ResponseTiming.new(observation),
      active_tool_calls: %{},
      command: command,
      generation_complete?: false,
      output_admitted?: false,
      output_retired?: false,
      supported_segments: [],
      order: state.next_sequence,
      speech_requests: %{},
      pending_speech: 0
    }

    %{state | agent_turns: Map.put(state.agent_turns, key(command), turn)}
  end

  def begin_speech(state, %TextToSpeechRequest{} = request) do
    update(state, request, fn turn ->
      requests = Map.put(Map.get(turn, :speech_requests, %{}), request.output_id, request)
      Map.merge(turn, %{speech_requests: requests, pending_speech: map_size(requests)})
    end)
  end

  def speech_targets(state, command) do
    case get(state, command) do
      nil -> []
      turn -> turn |> Map.get(:speech_requests, %{}) |> Map.values()
    end
  end

  def finish_speech(state, %TextToSpeechRequest{} = request) do
    case get(state, request) do
      %{speech_requests: requests} = turn ->
        if Map.get(requests, request.output_id) == request do
          remaining = Map.delete(requests, request.output_id)
          turn = %{turn | speech_requests: remaining, pending_speech: map_size(remaining)}
          {:ok, replace(state, request, turn)}
        else
          :stale
        end

      _untracked ->
        :stale
    end
  end

  @spec get(State.t(), struct()) :: map() | nil
  def get(%State{} = state, command), do: Map.get(state.agent_turns, key(command))

  def idle_targets(state, command) do
    case get(state, command) do
      nil ->
        {:error, :stale}

      origin ->
        others = state.agent_turns |> Map.delete(key(command)) |> Map.values()

        if Enum.all?(others, &(&1.order < origin.order and &1.generation_complete?)) do
          {:ok, Enum.filter(others, & &1.output_admitted?)}
        else
          {:error, :stale}
        end
    end
  end

  @spec mode(State.t()) :: :listener | :speaker
  def mode(%State{} = state) do
    if Enum.any?(state.agent_turns, fn {_key, turn} -> Map.get(turn, :output_admitted?, false) end),
       do: :speaker,
       else: :listener
  end

  @spec admit_output(State.t(), struct()) :: State.t()
  def admit_output(%State{} = state, command) do
    if output_eligible?(state, command),
      do: update(state, command, &Map.put(&1, :output_admitted?, true)),
      else: state
  end

  @spec output_eligible?(State.t(), struct()) :: boolean()
  def output_eligible?(%State{} = state, command) do
    case get(state, command) do
      nil -> false
      turn -> not Map.get(turn, :output_retired?, false)
    end
  end

  @spec retire_connection_output(State.t(), String.t()) :: State.t()
  def retire_connection_output(%State{} = state, connection_id) do
    turns =
      Map.new(state.agent_turns, fn {key, turn} ->
        if turn.command.connection_id == connection_id do
          {key, Map.merge(turn, %{output_admitted?: false, output_retired?: true})}
        else
          {key, turn}
        end
      end)

    %{state | agent_turns: turns}
  end

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
  defp command_id(%Context{} = context), do: context.command_id
end
