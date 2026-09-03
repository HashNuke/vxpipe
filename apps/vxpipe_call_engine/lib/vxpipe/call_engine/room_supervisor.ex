defmodule Vxpipe.CallEngine.RoomSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Vxpipe.CallEngine.Command.{CreateRoom, JoinParticipant}
  alias Vxpipe.CallEngine.{Error, Id, RoomAuthority, RoomIncarnationSupervisor}

  def start_link(_options) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  def create_room(%CreateRoom{} = command) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {command.tenant_id, command.room_id}) do
      [] -> start_room(command)
      [_room] -> {:error, room_already_exists(command.room_id)}
    end
  end

  def join_participant(%JoinParticipant{} = command) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {command.tenant_id, command.room_id}) do
      [{room_authority, _value}] -> RoomAuthority.join_participant(room_authority, command)
      [] -> {:error, room_not_found(command.room_id)}
    end
  end

  defp start_room(command) do
    incarnation_id = Id.generate(:room_incarnation)
    options = [command: command, incarnation_id: incarnation_id]

    case DynamicSupervisor.start_child(__MODULE__, {RoomIncarnationSupervisor, options}) do
      {:ok, _supervisor} ->
        {:ok, RoomAuthority.snapshot(command.tenant_id, command.room_id)}

      {:error, {:shutdown, {:failed_to_start_child, RoomAuthority, {:already_started, _pid}}}} ->
        {:error, room_already_exists(command.room_id)}

      {:error, _reason} ->
        {:error,
         Error.new(
           :room_start_failed,
           "The room incarnation could not be started.",
           retryable: true
         )}
    end
  end

  defp room_already_exists(room_id) do
    Error.new(
      :room_already_exists,
      "The room already exists.",
      details: %{"room_id" => room_id}
    )
  end

  defp room_not_found(room_id) do
    Error.new(
      :room_not_found,
      "The room does not exist.",
      details: %{"room_id" => room_id}
    )
  end
end
