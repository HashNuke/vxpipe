defmodule Vxpipe.Artifacts.Manifest do
  @moduledoc "Terminal evidence for one attempted streamed artifact."

  alias Vxpipe.Artifacts.ArtifactSpec

  @enforce_keys [
    :artifact_id,
    :tenant_id,
    :call_id,
    :room_id,
    :incarnation_id,
    :kind,
    :object_key,
    :sample_rate,
    :channels,
    :sample_format,
    :started_offset_samples,
    :ended_offset_samples,
    :sample_count,
    :accepted_chunks,
    :rejected_chunks,
    :gaps,
    :status,
    :terminal_reason
  ]
  defstruct @enforce_keys ++ [participant_id: nil, connection_id: nil, track_id: nil]

  @type status :: :complete | :incomplete
  @type t :: %__MODULE__{}

  @spec build(ArtifactSpec.t(), map(), non_neg_integer(), term()) :: t()
  def build(%ArtifactSpec{} = spec, progress, handoff_rejections, terminal_reason) do
    rejected = handoff_rejections + progress.failed_chunks
    status = status(rejected, progress.gaps, terminal_reason)

    %__MODULE__{
      artifact_id: spec.artifact_id,
      tenant_id: spec.tenant_id,
      call_id: spec.call_id,
      room_id: spec.room_id,
      incarnation_id: spec.incarnation_id,
      kind: spec.kind,
      object_key: spec.object_key,
      participant_id: spec.participant_id,
      connection_id: spec.connection_id,
      track_id: spec.track_id,
      sample_rate: spec.sample_rate,
      channels: spec.channels,
      sample_format: spec.sample_format,
      started_offset_samples: progress.started_offset_samples,
      ended_offset_samples: progress.ended_offset_samples,
      sample_count: progress.sample_count,
      accepted_chunks: progress.accepted_chunks,
      rejected_chunks: rejected,
      gaps: Enum.reverse(progress.gaps),
      status: status,
      terminal_reason: terminal_reason
    }
  end

  defp status(0, [], reason) when reason in [:normal, :shutdown], do: :complete
  defp status(_rejected, _gaps, _reason), do: :incomplete
end
