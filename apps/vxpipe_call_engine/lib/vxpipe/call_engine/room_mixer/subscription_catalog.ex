defmodule Vxpipe.CallEngine.RoomMixer.SubscriptionCatalog do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.MixedFrame
  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.RoomMixer.Subscription

  @enforce_keys [:entries, :monitors, :maximum_frames, :overflows]
  defstruct @enforce_keys

  @type entry :: %{
          token: reference(),
          recipient_id: String.t(),
          mode: MixedFrame.mode(),
          subscriber: pid(),
          monitor: reference(),
          queue: :queue.queue(MixedFrame.t()),
          notified?: boolean()
        }

  @type t :: %__MODULE__{
          entries: %{optional(String.t()) => entry()},
          monitors: %{optional(reference()) => String.t()},
          maximum_frames: pos_integer(),
          overflows: non_neg_integer()
        }

  @spec new(pos_integer()) :: t()
  def new(maximum_frames) when is_integer(maximum_frames) and maximum_frames > 0 do
    %__MODULE__{entries: %{}, monitors: %{}, maximum_frames: maximum_frames, overflows: 0}
  end

  @spec add(t(), keyword(), map(), Snapshot.t(), pid(), map()) ::
          {:ok, Subscription.t(), t()} | {:error, term()}
  def add(%__MODULE__{}, _options, _identity, nil, _mixer, _source_sequences),
    do: {:error, :policy_unavailable}

  def add(%__MODULE__{} = catalog, options, identity, snapshot, mixer, source_sequences) do
    with {:ok, id} <- nonempty(options, :id),
         :ok <- unique_subscription(catalog, id),
         :ok <- subscription_identity(options, identity),
         {:ok, recipient_id} <- nonempty(options, :recipient_participant_id),
         :ok <- present_recipient(recipient_id, snapshot),
         {:ok, mode} <- subscription_mode(Keyword.get(options, :mode), snapshot),
         subscriber when is_pid(subscriber) <- Keyword.get(options, :subscriber),
         :ok <- compatibility(catalog, recipient_id, mode, source_sequences) do
      token = make_ref()
      monitor = Process.monitor(subscriber)

      handle = %Subscription{
        id: id,
        mixer: mixer,
        token: token,
        tenant_id: identity.tenant_id,
        room_id: identity.room_id,
        incarnation_id: identity.incarnation_id,
        recipient_participant_id: recipient_id,
        mode: mode
      }

      entry = %{
        token: token,
        recipient_id: recipient_id,
        mode: mode,
        subscriber: subscriber,
        monitor: monitor,
        queue: :queue.new(),
        notified?: false
      }

      {:ok, handle,
       %{
         catalog
         | entries: Map.put(catalog.entries, id, entry),
           monitors: Map.put(catalog.monitors, monitor, id)
       }}
    else
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_subscription}
    end
  end

  @spec take(t(), String.t(), reference(), pos_integer(), pid()) ::
          {{:ok, [MixedFrame.t()]} | {:error, :unknown_subscription}, t()}
  def take(%__MODULE__{} = catalog, id, token, maximum_frames, mixer) do
    case Map.fetch(catalog.entries, id) do
      {:ok, %{token: ^token} = entry} ->
        {frames, queue} = take_queue(entry.queue, maximum_frames, [])
        entry = %{entry | queue: queue, notified?: false}
        entry = notify_if_pending(entry, mixer, id)
        entries = Map.put(catalog.entries, id, entry)
        {{:ok, Enum.reverse(frames)}, %{catalog | entries: entries}}

      _missing_or_wrong_token ->
        {{:error, :unknown_subscription}, catalog}
    end
  end

  @spec offer(t(), String.t(), MixedFrame.t(), pid()) ::
          {:ok, t()} | {:error, :full, t()}
  def offer(%__MODULE__{} = catalog, id, %MixedFrame{} = frame, mixer) do
    entry = Map.fetch!(catalog.entries, id)

    if :queue.len(entry.queue) >= catalog.maximum_frames do
      {:error, :full, %{catalog | overflows: catalog.overflows + 1}}
    else
      entry = %{entry | queue: :queue.in(frame, entry.queue)}
      entry = notify_if_pending(entry, mixer, id)
      {:ok, %{catalog | entries: Map.put(catalog.entries, id, entry)}}
    end
  end

  @spec clear(t()) :: {non_neg_integer(), t()}
  def clear(%__MODULE__{} = catalog) do
    {entries, dropped} =
      Enum.map_reduce(catalog.entries, 0, fn {id, entry}, count ->
        dropped = :queue.len(entry.queue)
        {{id, %{entry | queue: :queue.new(), notified?: false}}, count + dropped}
      end)

    {dropped, %{catalog | entries: Map.new(entries)}}
  end

  @spec remove_monitor(t(), reference()) :: t()
  def remove_monitor(%__MODULE__{} = catalog, monitor) do
    case Map.pop(catalog.monitors, monitor) do
      {nil, _monitors} -> catalog
      {id, monitors} -> %{catalog | entries: Map.delete(catalog.entries, id), monitors: monitors}
    end
  end

  @spec monitor_recipient?(t(), String.t()) :: boolean()
  def monitor_recipient?(%__MODULE__{} = catalog, recipient_id) do
    Enum.any?(catalog.entries, fn {_id, entry} ->
      entry.recipient_id == recipient_id and entry.mode != :mix_minus
    end)
  end

  defp notify_if_pending(%{notified?: false} = entry, mixer, id) do
    if :queue.is_empty(entry.queue) do
      entry
    else
      case :erlang.send(entry.subscriber, {:vxpipe_room_audio_available, mixer, id}, [:nosuspend]) do
        :nosuspend -> %{entry | queue: :queue.new()}
        _delivered -> %{entry | notified?: true}
      end
    end
  end

  defp notify_if_pending(entry, _mixer, _id), do: entry

  defp take_queue(queue, 0, frames), do: {frames, queue}

  defp take_queue(queue, remaining, frames) do
    case :queue.out(queue) do
      {{:value, frame}, queue} -> take_queue(queue, remaining - 1, [frame | frames])
      {:empty, queue} -> {frames, queue}
    end
  end

  defp subscription_identity(options, identity) do
    if Keyword.get(options, :tenant_id) == identity.tenant_id and
         Keyword.get(options, :room_id) == identity.room_id and
         Keyword.get(options, :incarnation_id) == identity.incarnation_id do
      :ok
    else
      {:error, :wrong_room}
    end
  end

  defp unique_subscription(catalog, id) do
    if Map.has_key?(catalog.entries, id),
      do: {:error, :duplicate_subscription},
      else: :ok
  end

  defp present_recipient(recipient_id, snapshot) do
    if MapSet.member?(snapshot.present_participant_ids, recipient_id),
      do: :ok,
      else: {:error, :recipient_not_present}
  end

  defp subscription_mode(mode, _snapshot) when mode in [:mix_minus, :full_mix], do: {:ok, mode}

  defp subscription_mode({:individual_track, source_id} = mode, snapshot)
       when is_binary(source_id) do
    if MapSet.member?(snapshot.present_participant_ids, source_id),
      do: {:ok, mode},
      else: {:error, :source_not_present}
  end

  defp subscription_mode(_mode, _snapshot), do: {:error, :invalid_subscription_mode}

  defp compatibility(catalog, recipient_id, :mix_minus, _source_sequences) do
    if monitor_recipient?(catalog, recipient_id),
      do: {:error, :conflicting_subscription},
      else: :ok
  end

  defp compatibility(catalog, recipient_id, _monitor_mode, source_sequences) do
    if Map.has_key?(source_sequences, recipient_id) or mix_minus_recipient?(catalog, recipient_id),
      do: {:error, :conflicting_subscription},
      else: :ok
  end

  defp mix_minus_recipient?(catalog, recipient_id) do
    Enum.any?(catalog.entries, fn {_id, entry} ->
      entry.recipient_id == recipient_id and entry.mode == :mix_minus
    end)
  end

  defp nonempty(options, key) do
    case Keyword.get(options, key) do
      value when is_binary(value) ->
        if String.trim(value) == "", do: {:error, :invalid_subscription}, else: {:ok, value}

      _invalid ->
        {:error, :invalid_subscription}
    end
  end
end
