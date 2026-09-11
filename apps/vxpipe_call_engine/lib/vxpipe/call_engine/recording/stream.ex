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
  defstruct @enforce_keys ++ [participant_id: nil, connection_id: nil, track_id: nil]

  @type mode :: :full_mix | {:individual_track, String.t(), String.t(), String.t()}

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          call_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          stream_id: String.t(),
          mode: mode(),
          participant_id: nil | String.t(),
          connection_id: nil | String.t(),
          track_id: nil | String.t(),
          sample_rate: pos_integer(),
          channels: pos_integer(),
          sample_format: :s16le
        }

  @spec new(map(), mode(), map()) ::
          {:ok, t()} | {:error, :invalid_recording_stream}
  def new(identity, mode, format) when is_map(identity) and is_map(format) do
    {participant_id, connection_id, track_id} = mode_identity(mode)

    stream = %__MODULE__{
      tenant_id: Map.get(identity, :tenant_id),
      call_id: Map.get(identity, :call_id),
      room_id: Map.get(identity, :room_id),
      incarnation_id: Map.get(identity, :incarnation_id),
      stream_id: stream_id(mode),
      mode: mode,
      participant_id: participant_id,
      connection_id: connection_id,
      track_id: track_id,
      sample_rate: Map.get(format, :sample_rate),
      channels: Map.get(format, :channels),
      sample_format: :s16le
    }

    if valid?(stream), do: {:ok, stream}, else: {:error, :invalid_recording_stream}
  end

  def new(_identity, _mode, _format), do: {:error, :invalid_recording_stream}

  defp valid?(stream) do
    identifiers?(stream) and mode_identity?(stream) and is_integer(stream.sample_rate) and
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

  defp mode_identity?(%__MODULE__{mode: :full_mix} = stream) do
    is_nil(stream.participant_id) and is_nil(stream.connection_id) and is_nil(stream.track_id)
  end

  defp mode_identity?(%__MODULE__{
         mode: {:individual_track, participant_id, connection_id, track_id}
       }) do
    Enum.all?([participant_id, connection_id, track_id], &valid_identifier?/1)
  end

  defp mode_identity?(_stream), do: false

  defp stream_id(:full_mix), do: "full-mix"

  defp stream_id({:individual_track, participant_id, connection_id, track_id}) do
    digest =
      {participant_id, connection_id, track_id}
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> binary_part(0, 12)
      |> Base.url_encode64(padding: false)

    "individual-#{digest}"
  end

  defp stream_id(_mode), do: ""

  defp mode_identity({:individual_track, participant_id, connection_id, track_id}),
    do: {participant_id, connection_id, track_id}

  defp mode_identity(_mode), do: {nil, nil, nil}
end
