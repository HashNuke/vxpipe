defmodule Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.ToolEvents do
  @moduledoc "Ordered admission and retirement of source-qualified STS tool evidence."

  alias Vxpipe.CallEngine.RoomAuthority.SpeechToSpeech.{Evidence, Tools}
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.{ToolCompletions, Tree}
  alias Vxpipe.CallEngine.Speech.Event

  def handle(state, capability, agent, evidence),
    do: handle(state, capability, agent, evidence, Evidence.policy_snapshot(state))

  def handle(state, capability, agent, %{event: %Event{sequence: sequence}} = evidence, policy)
      when is_integer(sequence) and sequence > 0 do
    if Evidence.current_agent?(state, capability, agent) and sequence > state.sts_tool_sequence do
      apply_event(state, capability, agent, evidence, policy)
    else
      state
    end
  end

  def handle(state, _capability, _agent, _evidence, _policy), do: state

  defp apply_event(
         state,
         capability,
         agent,
         %{event: %Event{kind: :tool_call} = event} = evidence,
         policy
       )
       when is_reference(event.call_ref) and
              (is_binary(event.turn_ref) or is_reference(event.turn_ref)) and
              is_binary(event.tool_name) and is_map(event.arguments) do
    if Evidence.tool_scope_current?(state, evidence, policy) do
      duplicate? = Map.has_key?(state.sts_tool_calls, event.call_ref)

      state =
        Tools.handle_tool_call(
          %{state | sts_tool_sequence: event.sequence},
          capability,
          agent,
          event.call_ref,
          event.turn_ref,
          event.tool_name,
          event.arguments
        )

      case Map.fetch(state.sts_tool_calls, event.call_ref) do
        {:ok, pending} when not duplicate? ->
          pending = Map.put(pending, :evidence, scope(evidence))
          %{state | sts_tool_calls: Map.put(state.sts_tool_calls, event.call_ref, pending)}

        _not_admitted ->
          state
      end
    else
      state
    end
  end

  defp apply_event(
         state,
         capability,
         _agent,
         %{event: %Event{kind: :tool_cancelled, call_ref: call, sequence: sequence}} = evidence,
         _policy
       )
       when is_reference(call) do
    case Map.get(state.sts_tool_calls, call) do
      %{evidence: admitted} = pending ->
        if admitted == scope(evidence) do
          # The transport association is lost, but the accepted operation still
          # owns its bounded worker and outcome. Completion must fail explicitly
          # if there is no valid result path; never resubmit business work.
          ToolCompletions.redeliver(Tree.tool_completions(capability), pending.tool_call_id)

          %{
            state
            | sts_tool_sequence: sequence,
              sts_tool_calls:
                Map.put(
                  state.sts_tool_calls,
                  call,
                  Map.put(pending, :delivery_unavailable?, true)
                )
          }
        else
          state
        end

      _unknown ->
        state
    end
  end

  defp apply_event(state, _capability, _agent, _evidence, _policy), do: state

  defp scope(evidence), do: Map.take(evidence, [:identity, :epoch, :audio_interval])
end
