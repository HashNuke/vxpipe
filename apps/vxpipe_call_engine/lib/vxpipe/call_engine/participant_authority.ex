defmodule Vxpipe.CallEngine.ParticipantAuthority do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Participant.Snapshot

  @snapshot_timeout 5_000

  def start_link(options) do
    command = Keyword.fetch!(options, :command)
    name = via(command.tenant_id, command.room_id, command.participant_id)
    GenServer.start_link(__MODULE__, options, name: name)
  end

  def child_spec(options) do
    command = Keyword.fetch!(options, :command)

    %{
      id: {__MODULE__, command.participant_id},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  def snapshot(participant_authority) do
    GenServer.call(participant_authority, :snapshot, @snapshot_timeout)
  end

  @impl true
  def init(options) do
    command = Keyword.fetch!(options, :command)
    incarnation_id = Keyword.fetch!(options, :incarnation_id)

    {:ok,
     %Snapshot{
       tenant_id: command.tenant_id,
       room_id: command.room_id,
       incarnation_id: incarnation_id,
       participant_id: command.participant_id,
       role: command.role,
       state: :joined,
       created_by_actor_id: command.actor_id,
       created_by_command_id: command.id
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, snapshot), do: {:reply, snapshot, snapshot}

  defp via(tenant_id, room_id, participant_id) do
    {:via, Registry,
     {Vxpipe.CallEngine.RoomRegistry, {:participant, tenant_id, room_id, participant_id}}}
  end
end
