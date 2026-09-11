defmodule Vxpipe.Gateway.Sideband.TransferControl do
  @moduledoc false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.ParticipantTransferControl
  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.Gateway.Session.Snapshot

  @command_timeout_seconds 5

  @spec submit(
          ParticipantTransferControl.action(),
          String.t(),
          String.t(),
          Snapshot.t(),
          ConnectionAttachment.t()
        ) :: :ok | {:error, :rejected}
  def submit(action, attempt_id, connection_id, %Snapshot{} = session, %ConnectionAttachment{})
      when action in [:accept, :media_ready] do
    result =
      with {:ok, command} <-
             ParticipantTransferControl.new(
               tenant_id: session.tenant_id,
               actor_id: session.actor_id,
               room_id: session.room_id,
               incarnation_id: session.incarnation_id,
               participant_id: session.participant_id,
               connection_id: connection_id,
               attempt_id: attempt_id,
               action: action,
               deadline: DateTime.add(DateTime.utc_now(), @command_timeout_seconds, :second)
             ),
           :ok <- CallEngine.participant_transfer_control(command) do
        :ok
      end

    case result do
      :ok -> :ok
      {:error, _reason} -> {:error, :rejected}
    end
  end
end
