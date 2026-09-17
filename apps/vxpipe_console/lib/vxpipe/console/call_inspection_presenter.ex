defmodule Vxpipe.Console.CallInspectionPresenter do
  @moduledoc "Converts database call-inspection records into the versioned JSON response."

  alias Vxpipe.CallEngine.CallDefinition.CapabilitySelection
  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.CallEngine.ResolvedCallPlan.Participant

  alias Vxpipe.CallEngine.Usage.EffectiveAmount

  alias Vxpipe.Calls.{
    ArchiveStatus,
    CallFact,
    CallHistory,
    CallSummary,
    CallTimelineEntry,
    PreparedCall,
    UsageReport,
    VariableSnapshot
  }

  alias Vxpipe.Console.CallInspectionResult

  @tool_kinds [
    :tool_call_started,
    :tool_call_completed,
    :tool_call_failed,
    :tool_call_cancelled
  ]
  @scalar_units [:tokens, :characters, :milliseconds, :requests]

  @spec present(CallInspectionResult.t()) :: map()
  def present(%CallInspectionResult{} = result) do
    participants = participants(result.prepared_call, result.history)
    {metrics, metrics_availability} = metrics(result.usage, result.history)

    %{
      "schema_version" => 1,
      "call" => call(result.call),
      "incarnation" => incarnation(result.prepared_call),
      "participants" => participants,
      "timeline" => timeline(result.history, participants),
      "variables" => variables(result.history),
      "metrics" => metrics,
      "metrics_availability" => metrics_availability,
      "completeness" => completeness(result.history.archive_status)
    }
  end

  defp call(%CallSummary{} = call) do
    %{
      "id" => call.id,
      "revision" => lifecycle_revision(call.state),
      "state" => Atom.to_string(call.state),
      "created_at" => instant(call.created_at),
      "started_at" => optional_instant(call.started_at),
      "ended_at" => optional_instant(call.ended_at),
      "terminal_reason" => optional_atom(call.terminal_reason),
      "duration_ms" => duration_ms(call)
    }
  end

  defp lifecycle_revision(:prepared), do: 1
  defp lifecycle_revision(:admitting), do: 2
  defp lifecycle_revision(:running), do: 3
  defp lifecycle_revision(state) when state in [:ended, :failed], do: 4

  defp duration_ms(%CallSummary{started_at: %DateTime{} = started, ended_at: %DateTime{} = ended}) do
    max(DateTime.diff(ended, started, :millisecond), 0)
  end

  defp duration_ms(_call), do: nil

  defp incarnation(%PreparedCall{room_id: room_id, incarnation_id: incarnation_id})
       when is_binary(room_id) and is_binary(incarnation_id) do
    %{"room_id" => room_id, "incarnation_id" => incarnation_id}
  end

  defp incarnation(%PreparedCall{}), do: nil

  defp participants(%PreparedCall{plan: %ResolvedCallPlan{} = plan}, history) do
    plan.participants
    |> Enum.sort_by(fn {definition_key, _participant} ->
      participant_order(definition_key, plan)
    end)
    |> Enum.map(fn {definition_key, participant} ->
      participant_entity(
        definition_key,
        participant,
        plan,
        history
      )
    end)
  end

  defp participant_order(id, plan) do
    cond do
      id == plan.entry_caller -> {0, id}
      id == plan.entry_receiver -> {1, id}
      true -> {2, id}
    end
  end

  defp participant_entity(
         definition_key,
         %Participant{} = participant,
         plan,
         history
       ) do
    id = participant.participant_id

    %{
      "id" => id,
      "revision" => participant_revision(id, history),
      "value" => %{
        "id" => id,
        "name" => participant_name(definition_key, plan),
        "role" => participant_role(definition_key, participant, plan),
        "state" => participant_state(id, history),
        "description" => participant.description,
        "connection" => connection(participant.connection),
        "capabilities" => capabilities(participant),
        "system_prompt" => participant.prompt,
        "transfer_policies" =>
          Enum.map(participant.transfers, &%{"name" => &1, "description" => ""}),
        "tools" => tools(participant)
      }
    }
  end

  defp participant_name(definition_key, plan) do
    if definition_key == plan.entry_caller, do: "Caller", else: humanize(definition_key)
  end

  defp participant_role(definition_key, _participant, plan)
       when definition_key == plan.entry_caller,
       do: "caller"

  defp participant_role(_id, %Participant{kind: :agent}, _definition), do: "agent"
  defp participant_role(_id, %Participant{kind: :human}, _definition), do: "human"

  defp participant_state(id, %CallHistory{facts: facts}) do
    facts
    |> Enum.filter(
      &(&1.participant_id == id and &1.kind in [:participant_joined, :participant_left])
    )
    |> Enum.max_by(& &1.sequence, fn -> nil end)
    |> case do
      %CallFact{kind: :participant_joined} -> "listening"
      %CallFact{kind: :participant_left} -> "left"
      nil -> "inactive"
    end
  end

  defp participant_revision(id, %CallHistory{facts: facts}) do
    facts
    |> Enum.filter(
      &(&1.participant_id == id and &1.kind in [:participant_joined, :participant_left])
    )
    |> Enum.map(& &1.sequence)
    |> Enum.max(fn -> 0 end)
  end

  defp connection(nil), do: nil
  defp connection(%{service: :web}), do: %{"kind" => "webrtc"}

  defp connection(%{number: number}) when is_binary(number),
    do: %{"kind" => "phone", "phone_number" => number}

  defp connection(_connection), do: nil

  defp capabilities(participant) do
    [
      participant.capabilities.speech_to_text,
      participant.capabilities.model_inference,
      participant.capabilities.text_to_speech
    ]
    |> Enum.map(&capability/1)
    |> Enum.reject(&is_nil/1)
  end

  defp capability(nil), do: nil

  defp capability(%CapabilitySelection{} = selection) do
    options = Map.get(selection, :options, %{})

    %{
      "name" => capability_name(selection.kind),
      "provider" => selection.provider,
      "model" =>
        Map.get(selection, :model) || Map.get(options, :model) || Map.get(options, "model")
    }
  end

  defp tools(%Participant{tools: tools}) do
    tools
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map(&%{"name" => &1, "description" => ""})
  end

  defp timeline(%CallHistory{} = history, participants) do
    participant_names =
      Map.new(participants, fn entity -> {entity["id"], entity["value"]["name"]} end)

    ordinary =
      history.timeline
      |> Enum.reject(&(&1.kind in @tool_kinds or &1.kind == :variable_snapshot))
      |> Enum.map(&timeline_entity(&1, participant_names))

    (ordinary ++ tool_entities(history.timeline))
    |> Enum.sort_by(fn entity ->
      {DateTime.to_unix(entity["occurred_at"], :microsecond), entity["source_sequence"],
       entity["id"]}
    end)
    |> Enum.map(&encode_timeline_time/1)
  end

  defp timeline_entity(%CallTimelineEntry{kind: :accepted_input} = entry, _names) do
    case Map.get(entry.payload, "content") do
      content when is_binary(content) -> message_entity(entry, content)
      _missing -> activity_entity(entry, %{})
    end
  end

  defp timeline_entity(%CallTimelineEntry{kind: :agent_output_generated} = entry, _names) do
    case Map.get(entry.payload, "text") do
      text when is_binary(text) -> message_entity(entry, text)
      _missing -> activity_entity(entry, %{})
    end
  end

  defp timeline_entity(%CallTimelineEntry{} = entry, names), do: activity_entity(entry, names)

  defp message_entity(entry, text) do
    %{
      "id" => entry.id,
      "revision" => revision(entry),
      "source_sequence" => entry.source_sequence,
      "kind" => "message",
      "occurred_at" => entry.occurred_at,
      "value" => %{
        "id" => entry.id,
        "participant_id" => entry.participant_id,
        "text" => text,
        "occurred_at" => instant(entry.occurred_at),
        "state" => "final"
      }
    }
  end

  defp activity_entity(entry, names) do
    %{
      "id" => entry.id,
      "revision" => revision(entry),
      "source_sequence" => entry.source_sequence,
      "kind" => "activity",
      "occurred_at" => entry.occurred_at,
      "value" => %{
        "id" => entry.id,
        "occurred_at" => instant(entry.occurred_at),
        "text" => activity_text(entry, names),
        "kind" => activity_kind(entry.kind)
      }
    }
  end

  defp tool_entities(entries) do
    entries
    |> Enum.filter(&(&1.kind in @tool_kinds and is_binary(&1.tool_call_id)))
    |> Enum.sort_by(& &1.source_sequence)
    |> Enum.reduce(%{}, fn entry, tools ->
      Map.update(tools, entry.tool_call_id, new_tool(entry), &update_tool(&1, entry))
    end)
    |> Map.values()
    |> Enum.map(&tool_entity/1)
  end

  defp new_tool(entry) do
    %{
      id: entry.tool_call_id,
      revision: revision(entry),
      source_sequence: entry.source_sequence,
      occurred_at: entry.occurred_at,
      name: Map.get(entry.payload, "name", "Tool call"),
      status: tool_status(entry.kind),
      request: optional_payload(entry.payload, "arguments"),
      response: tool_response(entry),
      response_status: response_status(entry.payload)
    }
  end

  defp update_tool(tool, entry) do
    tool
    |> Map.put(:revision, max(tool.revision, revision(entry)))
    |> Map.put(:source_sequence, max(tool.source_sequence, entry.source_sequence))
    |> Map.put(:status, tool_status(entry.kind))
    |> put_present(:request, optional_payload(entry.payload, "arguments"))
    |> put_present(:response, tool_response(entry))
    |> put_present(:response_status, response_status(entry.payload))
  end

  defp tool_entity(tool) do
    value = %{
      "id" => tool.id,
      "occurred_at" => instant(tool.occurred_at),
      "name" => tool.name,
      "status" => tool.status
    }

    value =
      value
      |> put_present("request", tool.request)
      |> put_present("response", tool.response)
      |> put_present("response_status", tool.response_status)

    %{
      "id" => tool.id,
      "revision" => tool.revision,
      "source_sequence" => tool.source_sequence,
      "kind" => "tool-call",
      "occurred_at" => tool.occurred_at,
      "value" => value
    }
  end

  defp encode_timeline_time(entity), do: Map.delete(entity, "occurred_at")

  defp tool_status(:tool_call_started), do: "pending"
  defp tool_status(:tool_call_completed), do: "completed"
  defp tool_status(kind) when kind in [:tool_call_failed, :tool_call_cancelled], do: "failed"

  defp tool_response(%CallTimelineEntry{kind: :tool_call_completed, payload: payload}),
    do: optional_payload(payload, "result")

  defp tool_response(%CallTimelineEntry{kind: :tool_call_failed, payload: payload}),
    do: optional_payload(payload, "reason")

  defp tool_response(_entry), do: :missing

  defp response_status(payload) do
    case Map.get(payload, "response_status", Map.get(payload, "status_code")) do
      status when is_integer(status) and status in 100..599 -> status
      _unknown -> :missing
    end
  end

  defp optional_payload(payload, key) do
    case Map.fetch(payload, key) do
      {:ok, value} -> {:present, value}
      :error -> :missing
    end
  end

  defp put_present(map, _key, :missing), do: map
  defp put_present(map, key, {:present, value}), do: Map.put(map, key, value)
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp activity_text(%CallTimelineEntry{kind: :participant_joined} = entry, names),
    do: "#{participant_label(entry.participant_id, names)} joined"

  defp activity_text(%CallTimelineEntry{kind: :participant_left} = entry, names),
    do: "#{participant_label(entry.participant_id, names)} left"

  defp activity_text(%CallTimelineEntry{kind: kind}, _names), do: humanize(kind)

  defp participant_label(nil, _names), do: "Participant"
  defp participant_label(id, names), do: Map.get(names, id, humanize(id))

  defp activity_kind(kind) when kind in [:participant_joined, :participant_left],
    do: "participant"

  defp activity_kind(kind)
       when kind in [
              :participant_transfer_started,
              :participant_transfer_completed,
              :participant_transfer_failed
            ],
       do: "transfer"

  defp activity_kind(_kind), do: "call"

  defp variables(%CallHistory{variable_snapshots: %{latest: %VariableSnapshot{} = snapshot}}) do
    %{
      "state" => "available",
      "value" => %{
        "revision" => snapshot.global_revision,
        "sections" =>
          Map.new(snapshot.sections, fn {name, section} ->
            {name, %{"revision" => section.revision, "value" => section.value}}
          end)
      }
    }
  end

  defp variables(%CallHistory{}), do: unavailable("not-captured")

  defp metrics({:available, %UsageReport{amounts: amounts}}, history) do
    observation_sequences = usage_observation_sequences(history)

    metrics =
      amounts
      |> Enum.filter(&(&1.unit in @scalar_units and is_integer(&1.quantity)))
      |> Enum.map(&metric(&1, observation_sequences))
      |> Enum.sort_by(& &1["id"])

    {metrics, %{"state" => "available"}}
  end

  defp metrics({:unavailable, _reason}, _history), do: {[], unavailable("not-loaded")}

  defp metric(%EffectiveAmount{} = amount, observation_sequences) do
    %{
      "id" => metric_id(amount),
      "revision" => metric_revision(amount, observation_sequences),
      "value" => %{
        "label" => humanize(amount.component),
        "value" => amount.quantity,
        "unit" => unit(amount.unit),
        "source" => "#{amount.provider.name} · #{humanize(amount.provenance)}",
        "description" => humanize(amount.component),
        "scope" => metric_scope(amount)
      }
    }
  end

  defp metric_id(%EffectiveAmount{} = amount) do
    identity = {
      amount.attempt_id,
      amount.capability,
      amount.provider,
      amount.attribution,
      amount.component,
      amount.unit,
      amount.provenance,
      amount.included_in
    }

    digest = :crypto.hash(:sha256, :erlang.term_to_binary(identity, [:deterministic]))
    "metric:" <> Base.url_encode64(digest, padding: false)
  end

  defp usage_observation_sequences(%CallHistory{facts: facts}) do
    facts
    |> Enum.filter(&(&1.kind == :usage_observed))
    |> Map.new(&{&1.id, &1.sequence})
  end

  defp metric_revision(%EffectiveAmount{observation_ids: observation_ids}, sequences) do
    observation_ids
    |> Enum.map(&Map.get(sequences, &1, 0))
    |> Enum.max(fn -> 0 end)
  end

  defp metric_scope(%EffectiveAmount{attribution: %{participant_id: participant_id}} = amount)
       when is_binary(participant_id) do
    %{
      "kind" => "participant-capability",
      "participant_id" => participant_id,
      "capability" => capability_name(amount.capability)
    }
  end

  defp metric_scope(%EffectiveAmount{} = amount) do
    %{"kind" => "room-capability", "capability" => capability_name(amount.capability)}
  end

  defp capability_name(:model_inference), do: "LLM"
  defp capability_name(:speech_to_text), do: "STT"
  defp capability_name(:text_to_speech), do: "TTS"
  defp capability_name(:tool), do: "Tool"
  defp capability_name(:telephony), do: "Telephony"

  defp unit(unit) when unit in @scalar_units, do: Atom.to_string(unit)

  defp completeness(%ArchiveStatus{} = status) do
    %{
      "state" => Atom.to_string(status.state),
      "missing_sequence_count" => status.missing_sequence_count,
      "dropped_live_records" => 0
    }
  end

  defp revision(%CallTimelineEntry{source_sequence: sequence}) when is_integer(sequence),
    do: sequence

  defp revision(_entry), do: 1

  defp unavailable(reason), do: %{"state" => "unavailable", "reason" => reason}

  defp optional_instant(nil), do: nil
  defp optional_instant(%DateTime{} = datetime), do: instant(datetime)
  defp optional_atom(nil), do: nil
  defp optional_atom(value) when is_atom(value), do: Atom.to_string(value)

  defp instant(%DateTime{} = datetime) do
    utc = DateTime.shift_zone!(datetime, "Etc/UTC")
    milliseconds = utc.microsecond |> elem(0) |> div(1_000) |> Integer.to_string()

    Calendar.strftime(utc, "%Y-%m-%dT%H:%M:%S") <>
      "." <> String.pad_leading(milliseconds, 3, "0") <> "Z"
  end

  defp humanize(value) when is_atom(value), do: value |> Atom.to_string() |> humanize()

  defp humanize(value) when is_binary(value) do
    value
    |> String.replace(~r/[_-]+/, " ")
    |> String.downcase()
    |> String.capitalize()
  end
end
