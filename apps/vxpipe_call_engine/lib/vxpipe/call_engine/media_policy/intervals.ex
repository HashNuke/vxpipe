defmodule Vxpipe.CallEngine.MediaPolicy.Intervals do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.{Snapshot, SpeechToTextDemand}

  @scopes [:speech_to_text, :audio_input, :audio_output]

  @doc false
  def unchanged?(%Snapshot{} = previous, %Snapshot{} = snapshot, scope, participant)
      when scope in @scopes,
      do: signature(previous, scope, participant) == signature(snapshot, scope, participant)

  def next(nil, %Snapshot{intervals: intervals}) when is_map(intervals), do: intervals

  def next(previous, %Snapshot{} = snapshot) do
    participants = participants(previous, snapshot)

    scoped =
      Map.new(@scopes, fn scope ->
        intervals =
          Map.new(participants, fn participant ->
            revision =
              if previous != nil and
                   signature(previous, scope, participant) ==
                     signature(snapshot, scope, participant) do
                Snapshot.interval(previous, scope, participant)
              else
                snapshot.revision
              end

            {participant, revision}
          end)

        {scope, intervals}
      end)

    recording =
      if previous != nil and previous.effective.record_audio == snapshot.effective.record_audio,
        do: Snapshot.interval(previous, :recording),
        else: snapshot.revision

    Map.put(scoped, :recording, recording)
  end

  def valid?(nil, _revision), do: true

  def valid?(intervals, revision) when is_map(intervals) do
    valid_revision?(Map.get(intervals, :recording), revision) and
      Enum.all?(@scopes, fn scope ->
        case Map.get(intervals, scope) do
          values when is_map(values) ->
            Enum.all?(values, fn {id, value} ->
              is_binary(id) and valid_revision?(value, revision)
            end)

          _invalid ->
            false
        end
      end)
  end

  def valid?(_intervals, _revision), do: false

  defp signature(snapshot, :speech_to_text, participant) do
    {present?(snapshot, participant), SpeechToTextDemand.required?(snapshot, participant),
     outgoing(snapshot.effective.transcript_routes, participant),
     snapshot.effective.save_transcripts}
  end

  defp signature(snapshot, :audio_input, participant) do
    {present?(snapshot, participant), outgoing(snapshot.effective.audio_routes, participant),
     snapshot.effective.record_audio}
  end

  defp signature(snapshot, :audio_output, participant) do
    {present?(snapshot, participant), incoming(snapshot.effective.audio_routes, participant)}
  end

  defp outgoing(:unrestricted, _participant), do: :unrestricted
  defp outgoing(routes, participant), do: Map.get(routes, participant, MapSet.new())

  defp incoming(:unrestricted, _participant), do: :unrestricted

  defp incoming(routes, participant) do
    for {source, recipients} <- routes,
        MapSet.member?(recipients, participant),
        into: MapSet.new(),
        do: source
  end

  defp present?(snapshot, participant),
    do: MapSet.member?(snapshot.present_participant_ids, participant)

  defp participants(nil, snapshot), do: snapshot.present_participant_ids

  defp participants(previous, snapshot) do
    retained =
      case previous.intervals do
        nil -> previous.present_participant_ids
        intervals -> intervals |> Map.fetch!(:speech_to_text) |> Map.keys() |> MapSet.new()
      end

    MapSet.union(retained, snapshot.present_participant_ids)
  end

  defp valid_revision?(value, maximum),
    do: is_integer(value) and value >= 0 and value <= maximum
end
