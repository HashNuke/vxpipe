defmodule Vxpipe.CallEngine.RoomMixer.Policy do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.RoomMixer.{State, SubscriptionCatalog, TimestampBuffer}

  @spec install(State.t(), Snapshot.t()) :: {:ok, State.t()} | {:error, term()}
  def install(%State{} = state, snapshot) do
    with :ok <- Snapshot.validate_transition(snapshot, state.policy) do
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
end
