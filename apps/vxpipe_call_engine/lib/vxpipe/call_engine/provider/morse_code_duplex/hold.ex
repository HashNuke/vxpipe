defmodule Vxpipe.CallEngine.Provider.MorseCodeDuplex.Hold do
  @moduledoc "Muted input and deferred tool replies for the Morse duplex fixture."

  alias Vxpipe.CallEngine.Provider.MorseCodeDuplex.ReplyFlow

  def set(state, true) do
    state = ReplyFlow.hold(state)
    log = Enum.take(state.hold_log ++ [{:hold, :started}], -16)
    {:reply, :ok, %{state | held?: true, hold_log: log}}
  end

  def set(state, false) do
    held_replies = state.held_tool_replies
    state = %{state | held?: false, held_tool_replies: []}

    result =
      Enum.reduce_while(held_replies, {:ok, state}, fn reply, {:ok, state} ->
        case ReplyFlow.enqueue(state, reply) do
          {:ok, state} -> {:cont, {:ok, state}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, state} ->
        log = Enum.take(state.hold_log ++ [{:hold, :ended}], -16)
        {:reply, :ok, %{state | hold_log: log}}

      {:error, reason} ->
        {:stop, {:shutdown, reason}, {:error, reason}, state}
    end
  end

  def queue_tool_reply(%{held?: true} = state, reply) do
    if length(state.held_tool_replies) >= 16,
      do: {:error, :pending_reply_overflow},
      else: {:ok, %{state | held_tool_replies: state.held_tool_replies ++ [reply]}}
  end

  def queue_tool_reply(state, reply), do: ReplyFlow.enqueue(state, reply)
end
