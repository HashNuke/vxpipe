defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.ToolEvents do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.{Input, Output, ResponseOrigins}
  alias Vxpipe.CallEngine.Speech.Event

  @maximum_pending 16

  def forward(state, %Event{kind: :tool_call, call_ref: call} = event) do
    cond do
      not permitted?(state) ->
        {:ok, state}

      not origin_current?(state, event.response_context) ->
        {:error, :stale_tool_origin}

      Map.has_key?(state.tool_calls, call) ->
        {:ok, state}

      map_size(state.tool_calls) >= @maximum_pending ->
        {:error, :pending_tool_overflow}

      true ->
        pending = %{
          turn_ref: event.turn_ref,
          evidence: evidence(state),
          response_context: event.response_context
        }

        send_event(state, pending.evidence, event)

        {:ok,
         %{
           state
           | tool_calls: Map.put(state.tool_calls, call, pending),
             tool_turns: MapSet.put(state.tool_turns, event.turn_ref)
         }}
    end
  end

  def forward(state, %Event{kind: :tool_cancelled, call_ref: call} = event) do
    case Map.fetch(state.tool_calls, call) do
      {:ok, pending} ->
        send_event(state, pending.evidence, event)
        {:ok, drop(state, call)}

      :error ->
        {:ok, state}
    end
  end

  def current?(state, call) do
    case Map.fetch(state.tool_calls, call) do
      {:ok, pending} ->
        permitted?(state) and pending.evidence == evidence(state) and
          origin_current?(state, pending.response_context)

      :error ->
        false
    end
  end

  def drop(state, call) do
    case Map.pop(state.tool_calls, call) do
      {nil, _calls} ->
        state

      {pending, calls} ->
        turns =
          if Enum.any?(calls, fn {_call, other} -> other.turn_ref == pending.turn_ref end),
            do: state.tool_turns,
            else: MapSet.delete(state.tool_turns, pending.turn_ref)

        %{state | tool_calls: calls, tool_turns: turns}
    end
  end

  def retire(state), do: %{state | tool_calls: %{}, tool_turns: MapSet.new()}

  defp permitted?(state),
    do: not state.held? and Output.audio_route_permitted?(state, state.human_id, state.agent_id)

  defp origin_current?(%{descriptor: %{response_start?: false}}, _context), do: true

  defp origin_current?(state, context) do
    case ResponseOrigins.accepted_fingerprint(state, context) do
      {:ok, fingerprint} -> ResponseOrigins.current?(state, fingerprint)
      :error -> false
    end
  end

  defp evidence(state) do
    %{
      identity: Map.put(state.frame_identity, :participant_id, state.human_id),
      epoch: state.input_epoch,
      audio_interval: Input.audio_interval(state, state.human_id)
    }
  end

  defp send_event(state, scope, event),
    do:
      send(
        state.owner,
        {:vxpipe_sts_tool_event, self(), state.agent_id, Map.put(scope, :event, event)}
      )
end
