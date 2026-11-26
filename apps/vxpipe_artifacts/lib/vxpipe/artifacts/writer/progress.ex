defmodule Vxpipe.Artifacts.Writer.Progress do
  @moduledoc """
  Bounded duplicate evidence for one streamed artifact writer.

  `duplicate_frames` is the exact count of folded duplicate frames.
  `selected_connection_ids` is only a bounded sample (first 64 distinct
  duplicate choices, sorted at manifest build): singleton delivery without
  duplicates persists no sample id, and sustained duplication keeps counting
  exactly while the sample stays capped.
  """

  alias Vxpipe.Artifacts.{ArtifactSpec, Chunk, Handoff, Manifest}

  @maximum_selected_connections 64

  @enforce_keys [
    :accepted_chunks,
    :failed_chunks,
    :sample_count,
    :started_offset_samples,
    :ended_offset_samples,
    :gaps,
    :duplicate_frames,
    :selected_connection_ids
  ]
  defstruct @enforce_keys

  @spec new() :: t()
  def new do
    %__MODULE__{
      accepted_chunks: 0,
      failed_chunks: 0,
      sample_count: 0,
      started_offset_samples: nil,
      ended_offset_samples: nil,
      gaps: [],
      duplicate_frames: 0,
      selected_connection_ids: MapSet.new()
    }
  end

  @spec accept(t(), Chunk.t()) :: t()
  def accept(%__MODULE__{} = progress, %Chunk{} = chunk) do
    expected_offset = progress.ended_offset_samples
    gaps = gap(expected_offset, chunk.offset_samples, progress.gaps)

    duplicates = Map.get(chunk, :recording_duplicate_frames, 0) || 0
    selected = Map.get(chunk, :recording_selected_connection_id)

    # Persist only actual duplicate choices: a singleton chunk with no folded
    # duplicates carries no sample even when it names the delivering listener.
    # The exact duplicate counter below always increments.
    selected_ids = progress.selected_connection_ids

    selected_ids =
      cond do
        not is_binary(selected) ->
          selected_ids

        not (is_integer(duplicates) and duplicates > 0) ->
          selected_ids

        MapSet.member?(selected_ids, selected) ->
          selected_ids

        MapSet.size(selected_ids) < @maximum_selected_connections ->
          MapSet.put(selected_ids, selected)

        true ->
          selected_ids
      end

    %{
      progress
      | accepted_chunks: progress.accepted_chunks + 1,
        sample_count: progress.sample_count + chunk.sample_count,
        started_offset_samples: progress.started_offset_samples || chunk.offset_samples,
        ended_offset_samples:
          max(expected_offset || 0, chunk.offset_samples + chunk.sample_count),
        gaps: gaps,
        duplicate_frames: progress.duplicate_frames + chunk.recording_duplicate_frames,
        selected_connection_ids: selected_ids
    }
  end

  @spec fail(t(), non_neg_integer()) :: t()
  def fail(progress, count \\ 1)

  def fail(%__MODULE__{} = progress, count) when is_integer(count) and count >= 0 do
    %{progress | failed_chunks: progress.failed_chunks + count}
  end

  @spec manifest(t(), ArtifactSpec.t(), Handoff.t(), term()) :: Manifest.t()
  def manifest(%__MODULE__{} = progress, spec, handoff, terminal_reason) do
    rejected = Handoff.stats(handoff).rejected
    Manifest.build(spec, progress, rejected, terminal_reason)
  end

  @type t :: %__MODULE__{
          accepted_chunks: non_neg_integer(),
          failed_chunks: non_neg_integer(),
          sample_count: non_neg_integer(),
          started_offset_samples: nil | non_neg_integer(),
          ended_offset_samples: nil | non_neg_integer(),
          gaps: [map()]
        }

  defp gap(nil, _offset, gaps), do: gaps

  defp gap(expected, offset, gaps) when offset > expected do
    [%{offset_samples: expected, sample_count: offset - expected} | gaps]
  end

  defp gap(_expected, _offset, gaps), do: gaps
end
