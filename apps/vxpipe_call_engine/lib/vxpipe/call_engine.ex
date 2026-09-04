defmodule Vxpipe.CallEngine do
  @moduledoc """
  Owns Vxpipe's protocol-neutral call lifecycle and processing runtime.
  """

  alias Vxpipe.CallEngine.Command.{AttachConnection, CreateRoom, JoinParticipant, SendText}
  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.Media.{AudioFrame, Ingress}
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
          {:ok, ConnectionAttachment.t()} | {:error, Error.t()}
  def attach_connection(%AttachConnection{} = command, output_sink \\ nil) do
    if DateTime.compare(command.deadline, DateTime.utc_now()) == :gt do
      settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

      case RoomSupervisor.attach_connection(
             command,
             Keyword.fetch!(settings, :speech_to_text),
             output_sink
           ) do
        {:ok, room_authority, media_ingress} ->
          {:ok,
           %ConnectionAttachment{
             room_monitor: Process.monitor(room_authority),
             media_ingress: media_ingress
           }}

        {:error, %Error{} = error} ->
          {:error, error}
      end
    else
      {:error,
       Error.new(
         :deadline_exceeded,
         "The attach-connection command deadline has elapsed."
       )}
    end
  end

  @spec push_audio(ConnectionAttachment.t(), AudioFrame.t()) ::
          :ok
          | {:error,
             :media_overloaded
             | :queue_full
             | :speech_to_text_unavailable
             | :stale_frame
             | :unavailable
             | :wrong_connection
             | :wrong_track}
  def push_audio(%ConnectionAttachment{media_ingress: nil}, %AudioFrame{}) do
    {:error, :speech_to_text_unavailable}
  end

  def push_audio(%ConnectionAttachment{media_ingress: media_ingress}, %AudioFrame{} = frame) do
    Ingress.push(media_ingress, frame)
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
