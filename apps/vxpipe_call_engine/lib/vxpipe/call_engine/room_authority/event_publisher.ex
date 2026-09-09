defmodule Vxpipe.CallEngine.RoomAuthority.EventPublisher do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.RoomAuthority.State

  @spec publish(State.t(), pid(), struct(), keyword()) :: State.t()
  def publish(%State{} = state, subscriber, event, attributes \\ [])
      when is_pid(subscriber) and is_list(attributes) do
    send(subscriber, {:vxpipe_event, event})
    archive_recorder = Recorder.event(state.archive_recorder, event, attributes)
    %{state | archive_recorder: archive_recorder}
  end
end
