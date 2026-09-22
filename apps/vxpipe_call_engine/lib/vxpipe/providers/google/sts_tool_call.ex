defmodule Vxpipe.Providers.Google.STSToolCall do
  @moduledoc false

  alias Vxpipe.CallEngine.Speech.Event

  @maximum_pending_tools 16

  def start(state, turn, id, name, args) do
    if map_size(state.pending_tools) >= @maximum_pending_tools do
      {:error, :session_failed}
    else
      call_ref = make_ref()

      case Event.emit(state.channel, :tool_call,
             call_ref: call_ref,
             turn_ref: turn,
             tool_name: name,
             arguments: args
           ) do
        :ok ->
          {:ok,
           %{
             state
             | pending_tools:
                 Map.put(state.pending_tools, call_ref, %{id: id, name: name, turn_ref: turn})
           }}

        :discarded ->
          {:ok, state}

        _failure ->
          {:error, :session_failed}
      end
    end
  end

  def cancel(state, id) do
    case Enum.find(state.pending_tools, fn {_call, tool} -> tool.id == id end) do
      {call_ref, _tool} ->
        case Event.emit(state.channel, :tool_cancelled, call_ref: call_ref) do
          :ok -> {:ok, %{state | pending_tools: Map.delete(state.pending_tools, call_ref)}}
          :discarded -> {:ok, %{state | pending_tools: Map.delete(state.pending_tools, call_ref)}}
          _failure -> {:error, :session_failed}
        end

      nil ->
        {:ok, state}
    end
  end
end
