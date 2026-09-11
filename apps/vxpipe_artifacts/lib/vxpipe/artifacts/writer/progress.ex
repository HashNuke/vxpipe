defmodule Vxpipe.Artifacts.Writer.Progress do
  @moduledoc false

  alias Vxpipe.Artifacts.{ArtifactSpec, Chunk, Handoff, Manifest}

  @enforce_keys [
    :accepted_chunks,
    :failed_chunks,
    :sample_count,
    :started_offset_samples,
    :ended_offset_samples,
    :gaps
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
      gaps: []
    }
  end

  @spec accept(t(), Chunk.t()) :: t()
  def accept(%__MODULE__{} = progress, %Chunk{} = chunk) do
    expected_offset = progress.ended_offset_samples
    gaps = gap(expected_offset, chunk.offset_samples, progress.gaps)

    %{
      progress
      | accepted_chunks: progress.accepted_chunks + 1,
        sample_count: progress.sample_count + chunk.sample_count,
        started_offset_samples: progress.started_offset_samples || chunk.offset_samples,
        ended_offset_samples:
          max(expected_offset || 0, chunk.offset_samples + chunk.sample_count),
        gaps: gaps
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
