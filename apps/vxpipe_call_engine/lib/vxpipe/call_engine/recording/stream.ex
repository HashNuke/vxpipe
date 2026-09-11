defmodule Vxpipe.CallEngine.Recording.Stream do
  @moduledoc "Immutable identity and PCM format for one room recording stream."

  @enforce_keys [
    :tenant_id,
    :call_id,
    :room_id,
    :incarnation_id,
    :stream_id,
    :mode,
    :sample_rate,
    :channels,
    :sample_format
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          call_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          stream_id: String.t(),
          mode: :full_mix,
          sample_rate: pos_integer(),
          channels: pos_integer(),
          sample_format: :s16le
        }

  @spec new(map(), :full_mix, map()) ::
          {:ok, t()} | {:error, :invalid_recording_stream}
  def new(identity, mode, format) when is_map(identity) and is_map(format) do
    stream = %__MODULE__{
      tenant_id: Map.get(identity, :tenant_id),
      call_id: Map.get(identity, :call_id),
      room_id: Map.get(identity, :room_id),
      incarnation_id: Map.get(identity, :incarnation_id),
      stream_id: stream_id(mode),
      mode: mode,
      sample_rate: Map.get(format, :sample_rate),
      channels: Map.get(format, :channels),
      sample_format: :s16le
    }

    if valid?(stream), do: {:ok, stream}, else: {:error, :invalid_recording_stream}
  end

  def new(_identity, _mode, _format), do: {:error, :invalid_recording_stream}

  defp valid?(stream) do
    identifiers?(stream) and mode?(stream.mode) and is_integer(stream.sample_rate) and
      stream.sample_rate > 0 and is_integer(stream.channels) and stream.channels > 0 and
      stream.channels <= 8
  end

  defp identifiers?(stream) do
    Enum.all?(
      [stream.tenant_id, stream.call_id, stream.room_id, stream.incarnation_id, stream.stream_id],
      &valid_identifier?/1
    )
  end

  defp valid_identifier?(value) do
    is_binary(value) and value != "" and byte_size(value) <= 128
  end

  defp mode?(:full_mix), do: true
  defp mode?(_mode), do: false

  defp stream_id(:full_mix), do: "full-mix"
  defp stream_id(_mode), do: ""
end
