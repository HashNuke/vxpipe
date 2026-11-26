defmodule Vxpipe.CallEngine.RoomMixer.Fanout do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.{MixedFrame, NormalizedFrame, PCM}
  alias Vxpipe.CallEngine.MediaPolicy.Snapshot

  alias Vxpipe.CallEngine.RoomMixer.{
    RecordingSelection,
    Router,
    SubscriptionCatalog,
    TimestampBuffer
  }

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

  defp sources(%{purpose: :recording, mode: :room_track}, _bucket, recording_only, policy) do
    # Room egress is already deduplicated at RecordingEgress admission to one
    # frame per room-clock timestamp. Fanout only forwards the surviving
    # transport-selected frame with its admission audit, never reselecting.
    if policy.effective.record_audio,
      do: {:ok, {:room, Router.recording_sources(recording_only, :room_track)}},
      else: :skip
  end

  defp sources(%{purpose: :recording, mode: mode}, bucket, recording_only, policy)
       when mode == :individual_tracks or
              (is_tuple(mode) and tuple_size(mode) == 2 and
                 (elem(mode, 0) == :individual_tracks or elem(mode, 0) == :individual_track)) do
    # Ingress (live human input) and recording-only (transport-selected agent
    # and room egress) buckets stay separate. Provenance decides the output
    # mode: ingress frames keep per-connection human modes even when the
    # human track is literally named "agent-egress"; recording-only frames
    # use the stable agent mode. Both sides are already deduplicated at
    # admission, so Fanout forwards every surviving frame without merging
    # maps (which would lose keys) or speculative reselecting.
    if policy.effective.record_audio do
      ingress = Router.recording_sources(bucket, mode)
      egress = Router.recording_sources(recording_only, mode)
      {:ok, {:individual, ingress, egress}}
    else
      :skip
    end
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

  defp deliver_frames({:room, frames}, %{entry: %{mode: :room_track}} = delivery, totals) do
    # Admission already reduced room egress to one frame per timestamp.
    # Forward each surviving frame with its counted duplicates and selected
    # connection; no fallback selection here.
    Enum.reduce(frames, totals, fn frame, totals ->
      offer([frame], :room_track, delivery, totals)
    end)
  end

  defp deliver_frames(
         {:individual, ingress, egress},
         delivery,
         totals
       ) do
    tagged_ingress = Enum.map(ingress, &{TimestampBuffer.source_key(&1), :ingress, &1})
    tagged_egress = Enum.map(egress, &{TimestampBuffer.source_key(&1), :egress, &1})

    (tagged_ingress ++ tagged_egress)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce(totals, fn {_key, provenance, frame}, totals ->
      concrete_mode =
        case provenance do
          :ingress ->
            {:individual_track, frame.source_participant_id, frame.connection_id, frame.track_id}

          :egress ->
            RecordingSelection.stable_agent_mode(frame.source_participant_id)
        end

      offer([frame], concrete_mode, delivery, totals)
    end)
  end

  defp deliver_frames(frames, %{entry: entry} = delivery, totals) when is_list(frames) do
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

  defp mixed_frame([frame], :room_track, delivery) do
    # Room-produced audio (opening audio, wait sounds, transfer and readiness
    # cues) is attributed to the room, never to the greeted caller or the
    # listener who happened to receive it. The surviving frame carries how
    # many duplicates were counted for its timestamp and which listener
    # connection was selected, so the terminal manifest can report them.
    %MixedFrame{
      tenant_id: delivery.identity.tenant_id,
      room_id: delivery.identity.room_id,
      incarnation_id: delivery.identity.incarnation_id,
      subscription_id: delivery.id,
      recipient_participant_id: delivery.entry.recipient_id,
      mode: :room_track,
      source_participant_ids: ["room"],
      timestamp: delivery.timestamp,
      output_generation: Map.get(delivery.entry, :output_generation, 0),
      policy_revision: SubscriptionCatalog.interval(delivery.entry, delivery.policy),
      sample_rate: delivery.format.sample_rate,
      channels: delivery.format.channels,
      payload: frame.payload,
      recording_duplicate_frames: Map.get(frame, :recording_duplicate_frames, 0) || 0,
      recording_selected_connection_id:
        Map.get(frame, :recording_selected_connection_id) || frame.connection_id
    }
  end

  defp mixed_frame([frame], {:individual_track, _, _, _} = mode, delivery) do
    %MixedFrame{
      tenant_id: delivery.identity.tenant_id,
      room_id: delivery.identity.room_id,
      incarnation_id: delivery.identity.incarnation_id,
      subscription_id: delivery.id,
      recipient_participant_id: delivery.entry.recipient_id,
      mode: mode,
      source_participant_ids: [frame.source_participant_id],
      timestamp: delivery.timestamp,
      output_generation: Map.get(delivery.entry, :output_generation, 0),
      policy_revision: SubscriptionCatalog.interval(delivery.entry, delivery.policy),
      sample_rate: delivery.format.sample_rate,
      channels: delivery.format.channels,
      payload: frame.payload,
      recording_duplicate_frames: Map.get(frame, :recording_duplicate_frames, 0) || 0,
      recording_selected_connection_id:
        Map.get(frame, :recording_selected_connection_id) || frame.connection_id
    }
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
