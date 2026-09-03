defmodule Vxpipe.CallEngine.RoomAuthority do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Command.CreateRoom
  alias Vxpipe.CallEngine.Room.Snapshot

  @snapshot_timeout 5_000

  def start_link(options) do
    command = Keyword.fetch!(options, :command)
    name = via(command.tenant_id, command.room_id)
    GenServer.start_link(__MODULE__, options, name: name)
  end

  def snapshot(tenant_id, room_id) do
    GenServer.call(via(tenant_id, room_id), :snapshot, @snapshot_timeout)
  end

  @impl true
  def init(options) do
    command = Keyword.fetch!(options, :command)
    incarnation_id = Keyword.fetch!(options, :incarnation_id)

    {:ok, build_snapshot(command, incarnation_id)}
  end

  @impl true
  def handle_call(:snapshot, _from, snapshot), do: {:reply, snapshot, snapshot}

  defp build_snapshot(%CreateRoom{} = command, incarnation_id) do
    %Snapshot{
      tenant_id: command.tenant_id,
      room_id: command.room_id,
      incarnation_id: incarnation_id,
      lifecycle: :open,
      created_by_actor_id: command.actor_id,
      created_by_command_id: command.id
    }
  end

  defp via(tenant_id, room_id) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {tenant_id, room_id}}}
  end
end
