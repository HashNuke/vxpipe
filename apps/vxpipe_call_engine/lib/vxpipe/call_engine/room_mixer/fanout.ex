defmodule Vxpipe.CallEngine.RoomMixer.Fanout do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.{MixedFrame, NormalizedFrame, PCM}
  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.RoomMixer.{Router, SubscriptionCatalog, TimestampBuffer}

  @spec deliver(
          [{non_neg_integer(), %{TimestampBuffer.source_key() => NormalizedFrame.t()}}],
          [{non_neg_integer(), %{TimestampBuffer.source_key() => NormalizedFrame.t()}}],
          SubscriptionCatalog.t(),
          map(),
          map(),
          Snapshot.t(),
          pid()
        ) :: {SubscriptionCatalog.t(), non_neg_integer(), non_neg_integer()}
  def deliver(buckets, recording_buckets, catalog, identity, format, policy, mixer) do
    room = Map.new(buckets)
    recording_only = Map.new(recording_buckets)

    timestamps =
      room
      |> Map.keys()
      |> Kernel.++(Map.keys(recording_only))
      |> Enum.uniq()
      |> Enum.sort()

    Enum.reduce(timestamps, {catalog, 0, 0}, fn timestamp, totals ->
      deliver_bucket(
        timestamp,
        Map.get(room, timestamp, %{}),
        Map.get(recording_only, timestamp, %{}),
        identity,
        format,
        policy,
        mixer,
        totals
      )
    end)
  end

  defp deliver_bucket(
         timestamp,
         bucket,
         recording_only,
         identity,
         format,
         policy,
         mixer,
         totals
       ) do
    subscription_ids = Map.keys(elem(totals, 0).entries)

    Enum.reduce(subscription_ids, totals, fn id, current ->
      deliver_subscription(
        id,
        timestamp,
        bucket,
        recording_only,
        identity,
        format,
        policy,
        mixer,
        current
      )
    end)
  end

  defp deliver_subscription(
         id,
         timestamp,
         bucket,
         recording_only,
         identity,
         format,
         policy,
         mixer,
         {catalog, delivered, dropped}
       ) do
    entry = Map.fetch!(catalog.entries, id)

    delivery = %{
      id: id,
      entry: entry,
      timestamp: timestamp,
      identity: identity,
      format: format,
      policy: policy,
      mixer: mixer
    }

    case sources(entry, bucket, recording_only, policy) do
      {:ok, frames} ->
        deliver_frames(frames, delivery, {catalog, delivered, dropped})

      :skip ->
        {catalog, delivered, dropped}
    end
  end

  defp sources(%{purpose: :recording, mode: mode}, bucket, recording_only, policy) do
    if policy.effective.record_audio,
      do: {:ok, Router.recording_sources(Map.merge(bucket, recording_only), mode)},
      else: :skip
  end

  defp sources(%{purpose: :participant, output_held?: true}, _bucket, _recording_only, _policy),
    do: :skip

  defp sources(%{purpose: :participant} = entry, bucket, _recording_only, policy) do
    if MapSet.member?(policy.present_participant_ids, entry.recipient_id) do
      frames = Router.sources(bucket, entry.recipient_id, entry.mode, policy.effective)
      cutoffs = Map.get(entry, :source_cutoffs, %{})

      {:ok,
       Enum.reject(frames, fn frame ->
         frame.sequence_number <= Map.get(cutoffs, TimestampBuffer.source_key(frame), -1)
       end)}
    else
      :skip
    end
  end

  defp deliver_frames(
         frames,
         %{entry: %{mode: mode}} = delivery,
         totals
       )
       when mode == :individual_tracks or
              (is_tuple(mode) and tuple_size(mode) == 2 and
                 elem(mode, 0) == :individual_tracks) do
    Enum.reduce(frames, totals, fn frame, totals ->
      concrete_mode =
        {:individual_track, frame.source_participant_id, frame.connection_id, frame.track_id}

      offer([frame], concrete_mode, delivery, totals)
    end)
  end

  defp deliver_frames(frames, %{entry: entry} = delivery, totals) do
    offer(frames, entry.mode, delivery, totals)
  end

  defp offer([], _mode, _delivery, totals), do: totals

  defp offer(
         frames,
         mode,
         delivery,
         {catalog, delivered, dropped}
       ) do
    frame = mixed_frame(frames, mode, delivery)

    case SubscriptionCatalog.offer(catalog, delivery.id, frame, delivery.mixer) do
      {:ok, catalog} -> {catalog, delivered + 1, dropped}
      {:error, :full, catalog} -> {catalog, delivered, dropped + 1}
    end
  end

  defp mixed_frame(frames, mode, delivery) do
    {:ok, payload} = PCM.mix(Enum.map(frames, & &1.payload))

    %MixedFrame{
      tenant_id: delivery.identity.tenant_id,
      room_id: delivery.identity.room_id,
      incarnation_id: delivery.identity.incarnation_id,
      subscription_id: delivery.id,
      recipient_participant_id: delivery.entry.recipient_id,
      mode: mode,
      source_participant_ids: frames |> Enum.map(& &1.source_participant_id) |> Enum.uniq(),
      timestamp: delivery.timestamp,
      output_generation: Map.get(delivery.entry, :output_generation, 0),
      policy_revision: SubscriptionCatalog.interval(delivery.entry, delivery.policy),
      sample_rate: delivery.format.sample_rate,
      channels: delivery.format.channels,
      payload: payload
    }
  end
end
