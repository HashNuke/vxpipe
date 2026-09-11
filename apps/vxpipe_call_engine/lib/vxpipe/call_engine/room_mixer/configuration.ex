defmodule Vxpipe.CallEngine.RoomMixer.Configuration do
  @moduledoc false

  alias Vxpipe.CallEngine.RoomMixer.{State, SubscriptionCatalog, TimestampBuffer}

  @spec new(keyword()) :: {:ok, State.t()} | {:error, term()}
  def new(options) when is_list(options) do
    with {:ok, identity} <- identity(options),
         {:ok, format} <- format(options),
         {:ok, maximum_buffered_timestamps} <- positive(options, :maximum_buffered_timestamps),
         {:ok, maximum_sink_frames} <- positive(options, :maximum_sink_frames) do
      {:ok,
       %State{
         identity: identity,
         format: format,
         policy: nil,
         buffer: TimestampBuffer.new(maximum_buffered_timestamps),
         subscriptions: SubscriptionCatalog.new(maximum_sink_frames),
         source_sequences: %{},
         buffer_overflows: 0,
         policy_dropped_frames: 0
       }}
    end
  end

  defp identity(options) do
    with {:ok, tenant_id} <- nonempty(options, :tenant_id),
         {:ok, room_id} <- nonempty(options, :room_id),
         {:ok, incarnation_id} <- nonempty(options, :incarnation_id) do
      {:ok, %{tenant_id: tenant_id, room_id: room_id, incarnation_id: incarnation_id}}
    end
  end

  defp format(options) do
    with {:ok, sample_rate} <- positive(options, :sample_rate),
         {:ok, channels} <- positive(options, :channels),
         {:ok, frame_samples} <- positive(options, :frame_samples) do
      {:ok, %{sample_rate: sample_rate, channels: channels, frame_samples: frame_samples}}
    end
  end

  defp positive(options, key) do
    case Keyword.get(options, key) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _invalid -> {:error, {:invalid_room_mixer_option, key}}
    end
  end

  defp nonempty(options, key) do
    case Keyword.get(options, key) do
      value when is_binary(value) ->
        if String.trim(value) == "",
          do: {:error, {:invalid_room_mixer_option, key}},
          else: {:ok, value}

      _invalid ->
        {:error, {:invalid_room_mixer_option, key}}
    end
  end
end
