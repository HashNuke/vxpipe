defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.ToolEvents do
  @moduledoc false

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.{Input, Output, ResponseOrigins}
  alias Vxpipe.CallEngine.Speech.Event
  alias Vxpipe.CallEngine.Tool.ConversationAdmission

  @maximum_pending 16

  def forward(state, %Event{kind: :tool_call, call_ref: call} = event) do
    cond do
      Map.has_key?(state.tool_calls, call) ->
        {:ok, state}

      not permitted?(state) ->
        {:error, :tool_not_permitted}

      not origin_current?(state, event.response_context) ->
        {:error, :stale_tool_origin}

      map_size(state.tool_calls) >= @maximum_pending ->
        {:error, :pending_tool_overflow}

      true ->
        pending = %{
          turn_ref: event.turn_ref,
          evidence: evidence(state),
          response_context: event.response_context,
          origin_fingerprint: ResponseOrigins.tool_fingerprint(state, event.response_context),
          conversation_mode: :blocking,
          admitted?: false,
          result_accepted?: false,
          cancelled?: false
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
      {:ok, %{result_accepted?: false} = pending} ->
        send_event(state, pending.evidence, event)
        {:ok, put_pending(state, call, %{pending | cancelled?: true})}

      {:ok, _accepted} ->
        {:ok, state}

      :error ->
        {:ok, state}
    end
  end

  def current?(state, call) do
    case Map.fetch(state.tool_calls, call) do
      {:ok, %{cancelled?: false, result_accepted?: false} = pending} ->
        Output.audio_route_permitted?(state, state.human_id, state.agent_id) and
          Map.delete(pending.evidence, :epoch) == Map.delete(evidence(state), :epoch) and
          pending_origin_current?(state, pending.origin_fingerprint)

      _unavailable ->
        false
    end
  end

  def holding?(state) do
    state.tool_calls
    |> Map.values()
    |> Enum.map(& &1.conversation_mode)
    |> ConversationAdmission.decide_modes()
    |> Kernel.!=(:admit)
  end

  def admit(state, call, mode, owner)
      when owner == state.owner and mode in [:blocking, :non_blocking] do
    case Map.fetch(state.tool_calls, call) do
      {:ok, %{admitted?: false} = pending} ->
        {:reply, :ok,
         put_pending(state, call, %{pending | admitted?: true, conversation_mode: mode})}

      _unavailable ->
        {:reply, {:error, :stale_request}, state}
    end
  end

  def admit(state, _call, _mode, _owner), do: {:reply, {:error, :unauthorized}, state}

  def finish(state, call, owner) when owner == state.owner do
    case Map.fetch(state.tool_calls, call) do
      {:ok, %{admitted?: true, result_accepted?: true}} -> {:reply, :ok, drop(state, call)}
      _unavailable -> {:reply, {:error, :stale_request}, state}
    end
  end

  def finish(state, _call, _owner), do: {:reply, {:error, :unauthorized}, state}

  def deliver_result(state, call, result, owner) when owner == state.owner do
    if current?(state, call) do
      case ResponseOrigins.submit(state, {:tool_result, call, result}) do
        {:ok, state} -> {:reply, :ok, accept_result(state, call)}
        {{:error, _reason} = error, state} -> {:reply, error, state}
      end
    else
      {:reply, {:error, :stale_request}, state}
    end
  end

  def deliver_result(state, _call, _result, _owner),
    do: {:reply, {:error, :unauthorized}, state}

  defp accept_result(state, call) do
    case Map.fetch!(state.tool_calls, call) do
      %{admitted?: true} = pending ->
        put_pending(state, call, %{pending | result_accepted?: true})

      _rejected_before_admission ->
        drop(state, call)
    end
  end

  defp put_pending(state, call, pending) do
    put_calls(state, Map.put(state.tool_calls, call, pending))
  end

  def drop(state, call), do: put_calls(state, Map.delete(state.tool_calls, call))

  defp put_calls(state, calls) do
    turns =
      calls
      |> Enum.reject(fn {_call, tool} -> tool.result_accepted? or tool.cancelled? end)
      |> MapSet.new(fn {_call, tool} -> tool.turn_ref end)

    %{state | tool_calls: calls, tool_turns: turns}
  end

  def retire(state), do: %{state | tool_calls: %{}, tool_turns: MapSet.new()}

  defp permitted?(state),
    do: not state.held? and Output.audio_route_permitted?(state, state.human_id, state.agent_id)

  defp pending_origin_current?(%{descriptor: %{response_start?: false}}, _context), do: true

  defp pending_origin_current?(state, fingerprint),
    do: ResponseOrigins.current_tool_fingerprint?(state, fingerprint)

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
