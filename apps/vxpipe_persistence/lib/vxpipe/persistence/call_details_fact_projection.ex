defmodule Vxpipe.Persistence.CallDetailsFactProjection do
  @moduledoc false

  alias Vxpipe.Calls.CallFact
  alias Vxpipe.Persistence.CallDetailsTimestamp

  @transcript_kinds [
    :participant_turn_started,
    :participant_transcription_final,
    :accepted_input,
    :participant_turn_completed,
    :agent_output_generated,
    :agent_output_delivery_started,
    :agent_output_delivery_progressed,
    :agent_output_delivered,
    :agent_turn_completed,
    :agent_turn_failed,
    :agent_turn_interrupted
  ]
  @tool_kinds [
    :tool_call_started,
    :tool_call_completed,
    :tool_call_failed,
    :tool_call_cancelled
  ]
  @transfer_kinds [
    :participant_transfer_started,
    :participant_transfer_completed,
    :participant_transfer_failed
  ]
  @participant_kinds [
    :participant_joined,
    :participant_left,
    :connection_attached,
    :connection_detached
  ]

  @spec sections([CallFact.t()]) :: map()
  def sections(facts) when is_list(facts) do
    %{
      transcript: selected(facts, @transcript_kinds),
      tools: selected(facts, @tool_kinds),
      transfers: selected(facts, @transfer_kinds)
    }
  end

  @spec participant_events([CallFact.t()], String.t()) :: [map()]
  def participant_events(facts, participant_id) do
    facts
    |> Enum.filter(&(&1.kind in @participant_kinds and &1.participant_id == participant_id))
    |> Enum.map(&document/1)
  end

  @spec document(CallFact.t()) :: map()
  def document(%CallFact{} = fact) do
    compact(%{
      "id" => fact.id,
      "kind" => Atom.to_string(fact.kind),
      "sequence" => fact.sequence,
      "public_sequence" => fact.public_sequence,
      "occurred_at" => CallDetailsTimestamp.format(fact.occurred_at),
      "participant_id" => fact.participant_id,
      "activation_id" => fact.activation_id,
      "source_participant_id" => fact.source_participant_id,
      "connection_id" => fact.connection_id,
      "command_id" => fact.command_id,
      "correlation_id" => fact.correlation_id,
      "tool_call_id" => fact.tool_call_id,
      "source_policy" => fact.source_policy,
      "payload" => fact.payload
    })
  end

  defp selected(facts, kinds) do
    facts
    |> Enum.filter(&(&1.kind in kinds))
    |> Enum.map(&document/1)
  end

  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)
end
