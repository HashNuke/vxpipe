defmodule Vxpipe.Console.CallRecording.Summary do
  @moduledoc "Safe operator-facing metadata for one recording artifact."

  alias Vxpipe.Calls.CallArtifact

  @enforce_keys [
    :id,
    :kind,
    :participant_id,
    :connection_id,
    :track_id,
    :sample_rate,
    :channels,
    :started_offset_samples,
    :ended_offset_samples,
    :sample_count,
    :accepted_chunks,
    :rejected_chunks,
    :gaps,
    :status,
    :terminal_reason,
    :playable?
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{}

  @spec new(CallArtifact.t(), boolean()) :: t()
  def new(%CallArtifact{} = artifact, playable?) when is_boolean(playable?) do
    %__MODULE__{
      id: artifact.id,
      kind: artifact.kind,
      participant_id: artifact.participant_id,
      connection_id: artifact.connection_id,
      track_id: artifact.track_id,
      sample_rate: artifact.sample_rate,
      channels: artifact.channels,
      started_offset_samples: artifact.started_offset_samples,
      ended_offset_samples: artifact.ended_offset_samples,
      sample_count: artifact.sample_count,
      accepted_chunks: artifact.accepted_chunks,
      rejected_chunks: artifact.rejected_chunks,
      gaps: artifact.gaps,
      status: artifact.status,
      terminal_reason: artifact.terminal_reason,
      playable?: playable?
    }
  end
end
