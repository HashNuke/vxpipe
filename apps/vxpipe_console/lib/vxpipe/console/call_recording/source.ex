defmodule Vxpipe.Console.CallRecording.Source do
  @moduledoc "A playable recording's safe metadata and private bounded reader."

  alias Vxpipe.Calls.CallArtifact
  alias Vxpipe.Console.CallRecording.Reader

  @derive {Inspect, except: [:reader]}
  @enforce_keys [
    :id,
    :kind,
    :participant_id,
    :connection_id,
    :track_id,
    :sample_rate,
    :channels,
    :sample_format,
    :started_offset_samples,
    :ended_offset_samples,
    :sample_count,
    :gaps,
    :status,
    :terminal_reason,
    :reader
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{}

  @spec new(CallArtifact.t(), term()) :: {:ok, t()} | {:error, atom()}
  def new(%CallArtifact{object_reference: reference} = artifact, reader)
      when is_map(reference) do
    if Reader.valid?(reader) do
      {:ok,
       %__MODULE__{
         id: artifact.id,
         kind: artifact.kind,
         participant_id: artifact.participant_id,
         connection_id: artifact.connection_id,
         track_id: artifact.track_id,
         sample_rate: artifact.sample_rate,
         channels: artifact.channels,
         sample_format: artifact.sample_format,
         started_offset_samples: artifact.started_offset_samples,
         ended_offset_samples: artifact.ended_offset_samples,
         sample_count: artifact.sample_count,
         gaps: artifact.gaps,
         status: artifact.status,
         terminal_reason: artifact.terminal_reason,
         reader: reader
       }}
    else
      {:error, :invalid_recording_reader}
    end
  end

  def new(%CallArtifact{}, _reader), do: {:error, :recording_unavailable}
  def new(_artifact, _reader), do: {:error, :invalid_recording_source}
end
