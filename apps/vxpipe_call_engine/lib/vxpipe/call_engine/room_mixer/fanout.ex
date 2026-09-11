defmodule Vxpipe.CallEngine.RoomMixer.Fanout do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.{MixedFrame, NormalizedFrame, PCM}
  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.RoomMixer.{Router, SubscriptionCatalog, TimestampBuffer}

  @spec deliver(
          [{non_neg_integer(), %{TimestampBuffer.source_key() => NormalizedFrame.t()}}],
          SubscriptionCatalog.t(),
          map(),
          map(),
          Snapshot.t(),
          pid()
        ) :: {SubscriptionCatalog.t(), non_neg_integer(), non_neg_integer()}
  def deliver(buckets, catalog, identity, format, policy, mixer) do
    Enum.reduce(buckets, {catalog, 0, 0}, fn {timestamp, bucket}, totals ->
      deliver_bucket(timestamp, bucket, identity, format, policy, mixer, totals)
    end)
  end

  defp deliver_bucket(timestamp, bucket, identity, format, policy, mixer, totals) do
    subscription_ids = Map.keys(elem(totals, 0).entries)

    Enum.reduce(subscription_ids, totals, fn id, current ->
      deliver_subscription(id, timestamp, bucket, identity, format, policy, mixer, current)
    end)
  end

  defp deliver_subscription(
         id,
         timestamp,
         bucket,
         identity,
         format,
         policy,
         mixer,
         {catalog, delivered, dropped}
       ) do
    entry = Map.fetch!(catalog.entries, id)

    case sources(entry, bucket, policy) do
      {:ok, frames} ->
        offer(
          frames,
          id,
          entry,
          timestamp,
          identity,
          format,
          policy,
          mixer,
          catalog,
          delivered,
          dropped
        )

      :skip ->
        {catalog, delivered, dropped}
    end
  end

  defp sources(%{purpose: :recording, mode: mode}, bucket, policy) do
    if policy.effective.record_audio,
      do: {:ok, Router.recording_sources(bucket, mode)},
      else: :skip
  end

  defp sources(%{purpose: :participant} = entry, bucket, policy) do
    if MapSet.member?(policy.present_participant_ids, entry.recipient_id) do
      {:ok, Router.sources(bucket, entry.recipient_id, entry.mode, policy.effective)}
    else
      :skip
    end
  end

  defp offer(
         [],
         _id,
         _entry,
         _timestamp,
         _identity,
         _format,
         _policy,
         _mixer,
         catalog,
         delivered,
         dropped
       ) do
    {catalog, delivered, dropped}
  end

  defp offer(
         frames,
         id,
         entry,
         timestamp,
         identity,
         format,
         policy,
         mixer,
         catalog,
         delivered,
         dropped
       ) do
    frame = mixed_frame(frames, id, entry, timestamp, identity, format, policy)

    case SubscriptionCatalog.offer(catalog, id, frame, mixer) do
      {:ok, catalog} -> {catalog, delivered + 1, dropped}
      {:error, :full, catalog} -> {catalog, delivered, dropped + 1}
    end
  end

  defp mixed_frame(frames, id, entry, timestamp, identity, format, policy) do
    {:ok, payload} = PCM.mix(Enum.map(frames, & &1.payload))

    %MixedFrame{
      tenant_id: identity.tenant_id,
      room_id: identity.room_id,
      incarnation_id: identity.incarnation_id,
      subscription_id: id,
      recipient_participant_id: entry.recipient_id,
      mode: entry.mode,
      source_participant_ids: frames |> Enum.map(& &1.source_participant_id) |> Enum.uniq(),
      timestamp: timestamp,
      policy_revision: policy.revision,
      sample_rate: format.sample_rate,
      channels: format.channels,
      payload: payload
    }
  end
end
