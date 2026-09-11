defmodule Vxpipe.CallEngine.RoomMixer.TimestampBuffer do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.NormalizedFrame

  @enforce_keys [:maximum_timestamps, :buckets, :last_flushed_timestamp]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          maximum_timestamps: pos_integer(),
          buckets: %{optional(non_neg_integer()) => %{String.t() => NormalizedFrame.t()}},
          last_flushed_timestamp: integer()
        }

  @spec new(pos_integer()) :: t()
  def new(maximum_timestamps) when is_integer(maximum_timestamps) and maximum_timestamps > 0 do
    %__MODULE__{
      maximum_timestamps: maximum_timestamps,
      buckets: %{},
      last_flushed_timestamp: -1
    }
  end

  @spec put(t(), NormalizedFrame.t()) ::
          {:ok, t()} | {:error, :buffer_full | :duplicate_frame | :stale_timestamp}
  def put(%__MODULE__{} = buffer, %NormalizedFrame{} = frame) do
    bucket = Map.get(buffer.buckets, frame.timestamp)

    cond do
      frame.timestamp <= buffer.last_flushed_timestamp ->
        {:error, :stale_timestamp}

      is_map(bucket) and Map.has_key?(bucket, frame.source_participant_id) ->
        {:error, :duplicate_frame}

      is_nil(bucket) and map_size(buffer.buckets) >= buffer.maximum_timestamps ->
        {:error, :buffer_full}

      true ->
        bucket = Map.put(bucket || %{}, frame.source_participant_id, frame)
        {:ok, %{buffer | buckets: Map.put(buffer.buckets, frame.timestamp, bucket)}}
    end
  end

  @spec take_through(t(), non_neg_integer()) ::
          {:ok, [{non_neg_integer(), map()}], t()} | {:error, :stale_timestamp}
  def take_through(%__MODULE__{} = buffer, timestamp)
      when is_integer(timestamp) and timestamp >= 0 do
    if timestamp <= buffer.last_flushed_timestamp do
      {:error, :stale_timestamp}
    else
      {ready, pending} =
        Enum.split_with(buffer.buckets, fn {bucket_timestamp, _frames} ->
          bucket_timestamp <= timestamp
        end)

      ready = Enum.sort_by(ready, &elem(&1, 0))

      {:ok, ready, %{buffer | buckets: Map.new(pending), last_flushed_timestamp: timestamp}}
    end
  end

  @spec clear(t()) :: {non_neg_integer(), t()}
  def clear(%__MODULE__{} = buffer) do
    dropped =
      Enum.reduce(buffer.buckets, 0, fn {_timestamp, bucket}, count ->
        count + map_size(bucket)
      end)

    {dropped, %{buffer | buckets: %{}}}
  end
end
