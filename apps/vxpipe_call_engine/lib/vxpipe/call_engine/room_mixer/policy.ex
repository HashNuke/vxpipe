defmodule Vxpipe.CallEngine.RoomMixer.Policy do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.Snapshot

  alias Vxpipe.CallEngine.RoomMixer.{
    RecordingEgress,
    State,
    SubscriptionCatalog,
    TimestampBuffer
  }

  @spec install(State.t(), Snapshot.t()) :: {:ok, State.t()} | {:error, term()}
  def install(%State{} = state, snapshot) do
    with {:ok, snapshot} <- Snapshot.prepare(snapshot, state.policy) do
      {buffer_dropped, buffer} =
        TimestampBuffer.retain(state.buffer, fn frame ->
          MapSet.member?(snapshot.present_participant_ids, frame.source_participant_id) and
            frame.policy_revision ==
              Snapshot.interval(snapshot, :audio_input, frame.source_participant_id)
        end)

      {egress_dropped, recording_egress} =
        RecordingEgress.install_policy(state.recording_egress, snapshot)

      {sink_dropped, subscriptions} =
        SubscriptionCatalog.install_policy(state.subscriptions, snapshot)

      {:ok,
       %{
         state
         | policy: snapshot,
           buffer: buffer,
           recording_egress: recording_egress,
           subscriptions: subscriptions,
           policy_dropped_frames:
             state.policy_dropped_frames + buffer_dropped + egress_dropped + sink_dropped
       }}
    end
  end
end
