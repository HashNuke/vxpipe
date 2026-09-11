defmodule Vxpipe.CallEngine.RoomMixer.Policy do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Snapshot}
  alias Vxpipe.CallEngine.RoomMixer.{State, SubscriptionCatalog, TimestampBuffer}

  @spec install(State.t(), Snapshot.t()) :: {:ok, State.t()} | {:error, term()}
  def install(%State{} = state, snapshot) do
    with :ok <- validate_snapshot(snapshot),
         :ok <- validate_revision(snapshot, state.policy) do
      {buffer_dropped, buffer} = TimestampBuffer.clear(state.buffer)
      {sink_dropped, subscriptions} = SubscriptionCatalog.clear(state.subscriptions)

      {:ok,
       %{
         state
         | policy: snapshot,
           buffer: buffer,
           subscriptions: subscriptions,
           policy_dropped_frames: state.policy_dropped_frames + buffer_dropped + sink_dropped
       }}
    end
  end

  defp validate_snapshot(%Snapshot{} = snapshot) do
    if is_integer(snapshot.revision) and snapshot.revision >= 0 and
         is_struct(snapshot.present_participant_ids, MapSet) and
         Enum.all?(snapshot.present_participant_ids, &is_binary/1) and
         Effective.valid?(snapshot.effective) do
      :ok
    else
      {:error, :invalid_policy}
    end
  end

  defp validate_snapshot(_snapshot), do: {:error, :invalid_policy}

  defp validate_revision(_snapshot, nil), do: :ok

  defp validate_revision(snapshot, current) do
    cond do
      snapshot.revision <= current.revision -> {:error, :stale_policy_revision}
      snapshot.revision == current.revision + 1 -> :ok
      true -> {:error, :unexpected_policy_revision}
    end
  end
end
