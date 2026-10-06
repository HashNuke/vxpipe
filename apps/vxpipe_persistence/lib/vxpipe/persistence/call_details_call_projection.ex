defmodule Vxpipe.Persistence.CallDetailsCallProjection do
  @moduledoc false

  alias Vxpipe.CallEngine.CallSpec.ConnectionIntent
  alias Vxpipe.CallEngine.ResolvedCallPlan.Participant
  alias Vxpipe.Calls.PreparedCall

  alias Vxpipe.Persistence.{
    CallDetailsFactProjection,
    CallDetailsSourceRead,
    CallDetailsTimestamp
  }

  alias Vxpipe.Persistence.Schema.TelephonyLeg

  @spec call(PreparedCall.t()) :: map()
  def call(%PreparedCall{} = call) do
    entry = Map.fetch!(call.plan.participants, call.entry_caller)

    %{
      "identity" => %{
        "call_id" => call.id,
        "tenant_key" => call.tenant_key,
        "call_spec_id" => call.call_spec_id,
        "call_spec_revision" => call.call_spec_revision,
        "call_spec_schema_version" => call.schema_version,
        "plan_digest" => "sha256:" <> Base.encode16(call.plan_digest, case: :lower)
      },
      "lifecycle" => %{
        "state" => Atom.to_string(call.state),
        "direction" => direction(entry.connection),
        "route" => route(call, entry),
        "created_at" => timestamp(call.created_at),
        "started_at" => timestamp(call.started_at),
        "ended_at" => timestamp(call.ended_at),
        "outgoing_outcome" => optional_atom(call.outgoing_outcome),
        "dial_submitted_at" => timestamp(call.dial_submitted_at),
        "answered_at" => timestamp(call.answered_at),
        "dial_ended_at" => timestamp(call.dial_ended_at),
        "terminal_reason" => optional_atom(call.terminal_reason)
      }
    }
  end

  @spec participants(CallDetailsSourceRead.t()) :: [map()]
  def participants(%CallDetailsSourceRead{} = read) do
    read.call.plan.participants
    |> Map.values()
    |> Enum.sort_by(& &1.call_spec_key)
    |> Enum.map(&participant(&1, read))
  end

  defp participant(%Participant{} = participant, read) do
    compact(%{
      "call_spec_key" => participant.call_spec_key,
      "participant_id" => participant.participant_id,
      "type" => Atom.to_string(participant.kind),
      "description" => participant.description,
      "connection" => connection(participant.connection),
      "activation_ids" => activation_ids(participant, read.facts),
      "events" =>
        CallDetailsFactProjection.participant_events(read.facts, participant.participant_id),
      "legs" => participant_legs(read.telephony_legs, participant.participant_id)
    })
  end

  defp activation_ids(participant, facts) do
    observed =
      facts
      |> Enum.filter(&(&1.participant_id == participant.participant_id))
      |> Enum.map(& &1.activation_id)

    [participant.activation_id | observed]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp participant_legs(legs, participant_id) do
    legs
    |> Enum.filter(&(&1.participant_id == participant_id))
    |> Enum.map(&leg/1)
  end

  defp leg(%TelephonyLeg{} = leg) do
    compact(%{
      "provider" => leg.provider,
      "service" => leg.service,
      "state" => leg.state,
      "provider_event_id" => leg.provider_event_id,
      "provider_connection_id" => leg.provider_connection_id,
      "provider_call_control_id" => leg.provider_call_control_id,
      "provider_call_leg_id" => leg.provider_call_leg_id,
      "provider_call_session_id" => leg.provider_call_session_id,
      "participant_ref" => leg.participant_ref,
      "participant_id" => leg.participant_id,
      "incarnation_id" => leg.incarnation_id,
      "accepted_at" => CallDetailsTimestamp.format(leg.accepted_at)
    })
  end

  defp route(call, participant) do
    participant.connection
    |> connection()
    |> Map.merge(%{
      "participant" => participant.call_spec_key,
      "participant_id" => participant.participant_id,
      "participant_key" => Map.get(call.participant_routes, participant.call_spec_key)
    })
    |> compact()
  end

  defp connection(nil), do: %{}

  defp connection(%ConnectionIntent{} = intent) do
    %{
      "service" => string(intent.service),
      "mode" => Atom.to_string(intent.mode),
      "admission" => Atom.to_string(intent.admission)
    }
  end

  defp direction(%ConnectionIntent{mode: :receive}), do: "inbound"
  defp direction(%ConnectionIntent{mode: :dial}), do: "outbound"
  defp direction(nil), do: "unknown"

  defp string(value) when is_atom(value), do: Atom.to_string(value)
  defp string(value), do: value

  defp optional_atom(nil), do: nil
  defp optional_atom(value), do: Atom.to_string(value)

  defp timestamp(value), do: CallDetailsTimestamp.format(value)

  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)
end
