defmodule Vxpipe.Artifacts.ArtifactSpec do
  @moduledoc "Immutable identity and audio format for one streamed call artifact."

  @fields [
    :tenant_id,
    :call_id,
    :room_id,
    :incarnation_id,
    :artifact_id,
    :object_key,
    :kind,
    :participant_id,
    :connection_id,
    :track_id,
    :sample_rate,
    :channels,
    :sample_format
  ]

  @enforce_keys [
    :tenant_id,
    :call_id,
    :room_id,
    :incarnation_id,
    :artifact_id,
    :object_key,
    :kind,
    :sample_rate,
    :channels,
    :sample_format
  ]
  defstruct @enforce_keys ++ [participant_id: nil, connection_id: nil, track_id: nil]

  @type kind :: :full_mix | :participant_track
  @type t :: %__MODULE__{
          tenant_id: String.t(),
          call_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          artifact_id: String.t(),
          object_key: String.t(),
          kind: kind(),
          participant_id: nil | String.t(),
          connection_id: nil | String.t(),
          track_id: nil | String.t(),
          sample_rate: pos_integer(),
          channels: pos_integer(),
          sample_format: :s16le
        }

  @spec new(t() | map()) :: {:ok, t()} | {:error, :invalid_artifact_spec}
  def new(%__MODULE__{} = spec), do: validate(spec)

  def new(value) when is_map(value) do
    if Enum.all?(Map.keys(value), &(&1 in @fields)) do
      value
      |> then(&struct(__MODULE__, &1))
      |> validate()
    else
      {:error, :invalid_artifact_spec}
    end
  rescue
    KeyError -> {:error, :invalid_artifact_spec}
  end

  def new(_value), do: {:error, :invalid_artifact_spec}

  defp validate(%__MODULE__{} = spec) do
    if identifiers?(spec) and format?(spec) and kind_identity?(spec) do
      {:ok, spec}
    else
      {:error, :invalid_artifact_spec}
    end
  end

  defp identifiers?(spec) do
    valid_string?(spec.tenant_id, 128) and valid_string?(spec.call_id, 128) and
      valid_string?(spec.room_id, 128) and valid_string?(spec.incarnation_id, 128) and
      valid_string?(spec.artifact_id, 128) and valid_string?(spec.object_key, 1_024)
  end

  defp format?(spec) do
    is_integer(spec.sample_rate) and spec.sample_rate > 0 and
      is_integer(spec.channels) and spec.channels > 0 and spec.channels <= 8 and
      spec.sample_format == :s16le
  end

  defp kind_identity?(%__MODULE__{kind: :full_mix} = spec) do
    is_nil(spec.participant_id) and is_nil(spec.connection_id) and is_nil(spec.track_id)
  end

  defp kind_identity?(%__MODULE__{kind: :participant_track} = spec) do
    valid_string?(spec.participant_id, 128) and valid_string?(spec.connection_id, 128) and
      valid_string?(spec.track_id, 128)
  end

  defp kind_identity?(_spec), do: false

  defp valid_string?(value, maximum) do
    is_binary(value) and value != "" and byte_size(value) <= maximum
  end
end
