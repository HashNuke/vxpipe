defmodule Vxpipe.CallEngine.RoomMixer.RecordingSelection do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.NormalizedFrame

  @agent_track "agent-egress"

  @spec stable_agent_mode(String.t()) ::
          {:individual_track, String.t(), String.t(), String.t()}
  def stable_agent_mode(source_id) when is_binary(source_id) do
    {:individual_track, source_id, source_id, @agent_track}
  end

  @spec group_key(NormalizedFrame.t()) ::
          :room | {:source, String.t()} | {:connection, String.t(), String.t(), String.t()}
  def group_key(%NormalizedFrame{} = frame) do
    case Map.get(frame, :origin, :participant) do
      :room ->
        :room

      _participant ->
        if frame.track_id == @agent_track do
          {:source, frame.source_participant_id}
        else
          {:connection, frame.source_participant_id, frame.connection_id, frame.track_id}
        end
    end
  end

  @spec same_group?(NormalizedFrame.t(), NormalizedFrame.t()) :: boolean()
  def same_group?(%NormalizedFrame{} = a, %NormalizedFrame{} = b) do
    a.timestamp == b.timestamp and group_key(a) == group_key(b)
  end

  @spec equivalent_max_order(NormalizedFrame.t(), %{String.t() => non_neg_integer()}) ::
          non_neg_integer()
  def equivalent_max_order(%NormalizedFrame{} = frame, connection_order)
      when is_map(connection_order) do
    stored = Map.get(frame, :recording_equivalent_max_order)
    fallback = Map.get(connection_order, frame.connection_id, 0)

    cond do
      is_integer(stored) and stored >= 0 -> stored
      true -> fallback
    end
  end

  @spec admission_order(String.t(), %{String.t() => non_neg_integer()}) :: non_neg_integer()
  def admission_order(connection_id, connection_order) when is_binary(connection_id) do
    Map.get(connection_order, connection_id, 0)
  end

  @spec track_equivalent(NormalizedFrame.t(), NormalizedFrame.t(), %{
          String.t() => non_neg_integer()
        }) :: NormalizedFrame.t()
  def track_equivalent(%NormalizedFrame{} = kept, %NormalizedFrame{} = incoming, connection_order)
      when is_map(connection_order) do
    if kept.payload == incoming.payload do
      max_order =
        max(
          equivalent_max_order(kept, connection_order),
          admission_order(incoming.connection_id, connection_order)
        )

      %{kept | recording_equivalent_max_order: max_order}
    else
      kept
    end
  end

  @type resolution ::
          {:keep_first, non_neg_integer(), String.t()}
          | {:replace, non_neg_integer(), String.t()}
          | :distinct

  @spec resolve(NormalizedFrame.t(), NormalizedFrame.t(), %{String.t() => non_neg_integer()}) ::
          resolution()
  def resolve(%NormalizedFrame{} = kept, %NormalizedFrame{} = incoming, connection_order)
      when is_map(connection_order) do
    if same_group?(kept, incoming) do
      if kept.payload == incoming.payload do
        selected = Map.get(kept, :recording_selected_connection_id) || kept.connection_id
        {:keep_first, 1, selected}
      else
        kept_max = equivalent_max_order(kept, connection_order)
        incoming_order = Map.get(connection_order, incoming.connection_id, 0)
        kept_selected = Map.get(kept, :recording_selected_connection_id) || kept.connection_id

        cond do
          incoming_order > kept_max -> {:replace, 1, incoming.connection_id}
          incoming_order < kept_max -> {:keep_first, 1, kept_selected}
          # Same admission rank (should not happen for distinct connections):
          # fall back to first accepted to keep behaviour deterministic.
          # When the kept payload already represents several equivalent
          # arrivals, kept_max is the highest rank seen for that payload, so
          # a tie still prefers the preserved first equivalent frame.
          true -> {:keep_first, 1, kept_selected}
        end
      end
    else
      :distinct
    end
  end
end
