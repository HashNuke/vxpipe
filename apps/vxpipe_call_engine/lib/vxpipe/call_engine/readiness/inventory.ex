defmodule Vxpipe.CallEngine.Readiness.Inventory do
  @moduledoc "Required room and participant paths derived from a pinned plan and prospective policy."

  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot, SpeechToTextDemand}
  alias Vxpipe.CallEngine.ResolvedCallPlan

  @enforce_keys [
    :policy,
    :participant_ids,
    :connections,
    :missing_participants,
    :participant_capabilities,
    :recording_participant_ids,
    :recording_targets,
    :room
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          policy: Snapshot.t(),
          participant_ids: MapSet.t(String.t()),
          connections: %{String.t() => map()},
          missing_participants: MapSet.t(String.t()),
          participant_capabilities: %{String.t() => MapSet.t(atom())},
          recording_participant_ids: MapSet.t(String.t()),
          recording_targets: list(),
          room: MapSet.t(atom())
        }

  @spec build(ResolvedCallPlan.t(), Snapshot.t(), map(), keyword()) ::
          {:ok, t()} | {:error, atom()}
  def build(%ResolvedCallPlan{} = plan, %Snapshot{} = policy, connections, options \\ []) do
    participants =
      Map.new(plan.participants, fn {_key, participant} ->
        {participant.participant_id, participant}
      end)

    with :ok <- validate_membership(participants, policy),
         {:ok, targets} <- recording_targets(plan, options) do
      present = Map.take(participants, MapSet.to_list(policy.present_participant_ids))
      connections = select_connections(connections, present, Keyword.get(options, :attempt_id))
      recorded = recording_participants(present, connections, targets, policy)

      {:ok,
       %__MODULE__{
         policy: policy,
         participant_ids: policy.present_participant_ids,
         connections: connection_demands(connections, present, policy, recorded),
         missing_participants: missing_participants(present, connections),
         participant_capabilities: participant_capabilities(present, policy, recorded),
         recording_participant_ids: recorded,
         recording_targets: targets,
         room: room_requirements(options)
       }}
    end
  end

  defp validate_membership(participants, policy) do
    cond do
      not Snapshot.valid?(policy) ->
        {:error, :invalid_policy}

      not MapSet.subset?(policy.present_participant_ids, MapSet.new(Map.keys(participants))) ->
        {:error, :unknown_participant}

      true ->
        :ok
    end
  end

  defp select_connections(connections, participants, attempt_id) do
    Map.filter(connections, fn {_id, connection} ->
      participant = Map.get(participants, connection.participant_id)
      participant != nil and participant.kind == :human and admitted?(connection, attempt_id)
    end)
  end

  defp admitted?(%{admission: :main}, _attempt_id), do: true

  defp admitted?(%{admission: :transfer_preparation, transfer_attempt_id: id}, id)
       when is_binary(id), do: true

  defp admitted?(_connection, _attempt_id), do: false

  defp connection_demands(connections, participants, policy, recorded) do
    connections
    |> Map.filter(fn {_id, connection} -> media_connection?(connection) end)
    |> Map.new(fn {id, connection} ->
      participant = Map.fetch!(participants, connection.participant_id)
      microphone? = connection.role == :human

      demand = [
        audio_input?: microphone? and audio_source?(participant.participant_id, policy, recorded),
        room_output?: audio_recipient?(participant.participant_id, policy),
        speech_to_text?:
          microphone? and participant.capabilities.speech_to_text != nil and
            SpeechToTextDemand.required?(policy, participant.participant_id)
      ]

      {id,
       %{
         participant_id: participant.participant_id,
         instance: connection.pid,
         admission: connection.admission,
         demand: demand
       }}
    end)
  end

  def media_connection?(%{output_sink: nil, speech_to_text: nil}), do: false
  def media_connection?(_connection), do: true

  defp missing_participants(participants, connections) do
    connected = MapSet.new(connections, fn {_id, connection} -> connection.participant_id end)

    participants
    |> Enum.filter(fn {_id, participant} -> participant.kind == :human end)
    |> MapSet.new(fn {id, _participant} -> id end)
    |> MapSet.difference(connected)
  end

  defp participant_capabilities(participants, policy, recorded) do
    participants
    |> Enum.filter(fn {_id, participant} -> participant.kind == :agent end)
    |> Map.new(fn {id, participant} ->
      selected = participant.capabilities

      capabilities = [
        model_inference: selected.model_inference != nil,
        speech_to_speech: selected.speech_to_speech != nil,
        text_to_speech: selected.text_to_speech != nil and audio_source?(id, policy, recorded)
      ]

      {id, MapSet.new(for {kind, true} <- capabilities, do: kind)}
    end)
    |> Map.reject(fn {_id, kinds} -> MapSet.size(kinds) == 0 end)
  end

  defp audio_source?(id, policy, recorded) do
    MapSet.member?(recorded, id) or
      Enum.any?(policy.present_participant_ids, fn recipient ->
        id != recipient and Effective.audio_route_permitted?(policy.effective, id, recipient)
      end)
  end

  defp audio_recipient?(id, policy) do
    Enum.any?(policy.present_participant_ids, fn source ->
      id != source and Effective.audio_route_permitted?(policy.effective, source, id)
    end)
  end

  defp recording_participants(participants, connections, targets, policy) do
    if policy.effective.record_audio do
      participants
      |> Enum.filter(fn {id, participant} ->
        recording_target?(targets, id) and recordable?(participant, connections)
      end)
      |> MapSet.new(fn {id, _participant} -> id end)
    else
      MapSet.new()
    end
  end

  defp recordable?(%{kind: :agent} = participant, _connections),
    do: participant.capabilities.text_to_speech != nil

  defp recordable?(participant, connections) do
    attached =
      Enum.filter(connections, fn {_id, connection} ->
        connection.participant_id == participant.participant_id
      end)

    attached == [] or
      Enum.any?(attached, fn {_id, connection} ->
        connection.role == :human and media_connection?(connection)
      end)
  end

  defp recording_target?(targets, id) do
    Enum.any?(targets, fn
      :full_mix -> true
      {:individual_tracks, ids} -> id in ids
    end)
  end

  defp recording_targets(plan, options) do
    settings = Keyword.get(options, :recording, [])

    if Keyword.get(settings, :enabled, false) do
      resolve_targets(Keyword.get(settings, :targets), plan)
    else
      {:ok, []}
    end
  end

  defp resolve_targets(targets, plan) when is_list(targets) and targets != [] do
    result =
      Enum.reduce_while(targets, {:ok, []}, fn target, {:ok, targets} ->
        case resolve_target(target, plan) do
          {:ok, target} -> {:cont, {:ok, targets ++ [target]}}
          :error -> {:halt, {:error, :invalid_recording_targets}}
        end
      end)

    with {:ok, targets} <- result,
         true <- length(targets) == length(Enum.uniq(targets)),
         true <- Enum.count(targets, &match?({:individual_tracks, _ids}, &1)) <= 1 do
      {:ok, targets}
    else
      _invalid -> {:error, :invalid_recording_targets}
    end
  end

  defp resolve_targets(_targets, _plan), do: {:error, :invalid_recording_targets}

  defp resolve_target(:full_mix, _plan), do: {:ok, :full_mix}

  defp resolve_target(:individual_tracks, plan) do
    {:ok,
     {:individual_tracks,
      plan.participants |> Map.values() |> Enum.map(& &1.participant_id) |> Enum.sort()}}
  end

  defp resolve_target({:individual_participants, keys}, plan) when is_list(keys) do
    if unique_nonempty?(keys) and Enum.all?(keys, &Map.has_key?(plan.participants, &1)) do
      {:ok,
       {:individual_tracks, Enum.map(keys, &Map.fetch!(plan.participants, &1).participant_id)}}
    else
      :error
    end
  end

  defp resolve_target({:individual_tracks, ids} = target, plan) when is_list(ids) do
    pinned =
      MapSet.new(plan.participants, fn {_key, participant} -> participant.participant_id end)

    if unique_nonempty?(ids) and Enum.all?(ids, &MapSet.member?(pinned, &1)),
      do: {:ok, target},
      else: :error
  end

  defp resolve_target(_target, _plan), do: :error

  defp unique_nonempty?(values), do: values != [] and length(values) == length(Enum.uniq(values))

  defp room_requirements(options) do
    optional = [
      archive: Keyword.get(options, :archive?, false),
      live_inspection: Keyword.get(options, :live_inspection?, false),
      recording: options |> Keyword.get(:recording, []) |> Keyword.get(:enabled, false)
    ]

    MapSet.new(
      [:room_mixer, :transcript_router, :call_variables] ++
        for({kind, true} <- optional, do: kind)
    )
  end
end
