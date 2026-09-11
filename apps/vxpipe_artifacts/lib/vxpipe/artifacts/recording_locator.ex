defmodule Vxpipe.Artifacts.RecordingLocator do
  @moduledoc false

  alias Vxpipe.CallEngine.Recording.Stream

  @spec specification(Stream.t()) :: map()
  def specification(%Stream{} = stream) do
    artifact_id = "artifact_" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

    %{
      tenant_id: stream.tenant_id,
      call_id: stream.call_id,
      room_id: stream.room_id,
      incarnation_id: stream.incarnation_id,
      artifact_id: artifact_id,
      object_key: object_key(stream, artifact_id),
      kind: :full_mix,
      sample_rate: stream.sample_rate,
      channels: stream.channels,
      sample_format: stream.sample_format
    }
  end

  defp object_key(stream, artifact_id) do
    encoded_path =
      [stream.tenant_id, stream.call_id, stream.incarnation_id]
      |> Enum.map(&Base.url_encode64(&1, padding: false))
      |> Enum.join("/")

    "calls/#{encoded_path}/recordings/#{artifact_id}.s16le"
  end
end
