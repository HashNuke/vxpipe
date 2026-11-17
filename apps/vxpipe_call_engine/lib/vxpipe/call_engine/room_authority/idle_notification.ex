defmodule Vxpipe.CallEngine.RoomAuthority.IdleNotification do
  @moduledoc false

  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.Id

  @notification """
  Vxpipe engine notification: the caller has provided no new input during the configured idle \
  interval. Follow your instructions to decide whether to speak, continue waiting silently, or \
  invoke a permitted tool. Do not infer that the caller disconnected.
  """

  def new(state, connection_id) do
    with {:ok, connection} <- Map.fetch(state.connections, connection_id) do
      SendText.new(
        id: Id.generate(:command),
        tenant_id: state.snapshot.tenant_id,
        actor_id: connection.actor_id,
        room_id: state.snapshot.room_id,
        incarnation_id: state.snapshot.incarnation_id,
        participant_id: connection.participant_id,
        connection_id: connection_id,
        correlation_id: Id.generate(:turn),
        content: @notification,
        run_immediately: false,
        audio_response: true,
        deadline: DateTime.add(DateTime.utc_now(), 5, :second)
      )
    else
      :error -> {:error, :unavailable}
    end
  end
end
