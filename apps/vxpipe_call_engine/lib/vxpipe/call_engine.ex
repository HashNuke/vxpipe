defmodule Vxpipe.CallEngine do
  @moduledoc """
  Owns Vxpipe's protocol-neutral call lifecycle and processing runtime.
  """

  alias Vxpipe.CallEngine.Command.CreateRoom
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
end
