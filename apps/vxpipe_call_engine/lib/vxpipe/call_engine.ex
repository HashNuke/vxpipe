defmodule Vxpipe.CallEngine do
  @moduledoc """
  Owns Vxpipe's protocol-neutral call lifecycle and processing runtime.
  """

  alias Vxpipe.CallEngine.Command.{AttachConnection, CreateRoom, JoinParticipant, SendText}
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.RoomSupervisor

  @spec create_room(CreateRoom.t()) ::
          {:ok, Vxpipe.CallEngine.Room.Snapshot.t()} | {:error, Error.t()}
  def create_room(%CreateRoom{} = command) do
    if DateTime.compare(command.deadline, DateTime.utc_now()) == :gt do
      RoomSupervisor.create_room(command)
    else
      {:error,
       Error.new(
         :deadline_exceeded,
         "The create-room command deadline has elapsed."
       )}
    end
  end

  @spec join_participant(JoinParticipant.t()) ::
          {:ok, Vxpipe.CallEngine.Participant.Snapshot.t()} | {:error, Error.t()}
  def join_participant(%JoinParticipant{} = command) do
    if DateTime.compare(command.deadline, DateTime.utc_now()) == :gt do
      RoomSupervisor.join_participant(command)
    else
      {:error,
       Error.new(
         :deadline_exceeded,
         "The join-participant command deadline has elapsed."
       )}
    end
  end

  @spec attach_connection(AttachConnection.t()) ::
          {:ok, reference()} | {:error, Error.t()}
  def attach_connection(%AttachConnection{} = command) do
    if DateTime.compare(command.deadline, DateTime.utc_now()) == :gt do
      case RoomSupervisor.attach_connection(command) do
        {:ok, room_authority} -> {:ok, Process.monitor(room_authority)}
        {:error, %Error{} = error} -> {:error, error}
      end
    else
      {:error,
       Error.new(
         :deadline_exceeded,
         "The attach-connection command deadline has elapsed."
       )}
    end
  end

  @spec send_text(SendText.t()) :: :ok | {:error, Error.t()}
  def send_text(%SendText{} = command) do
    if DateTime.compare(command.deadline, DateTime.utc_now()) == :gt do
      RoomSupervisor.send_text(command)
    else
      {:error,
       Error.new(
         :deadline_exceeded,
         "The send-text command deadline has elapsed."
       )}
    end
  end
end
