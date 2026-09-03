defmodule Vxpipe.CallEngine.RoomAuthority do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Command.{CreateRoom, JoinParticipant}
  alias Vxpipe.CallEngine.Room.Snapshot
  alias Vxpipe.CallEngine.RoomParticipantSupervisor

  @snapshot_timeout 5_000

  def start_link(options) do
    command = Keyword.fetch!(options, :command)
    name = via(command.tenant_id, command.room_id)
    GenServer.start_link(__MODULE__, options, name: name)
  end

  def snapshot(tenant_id, room_id) do
    GenServer.call(via(tenant_id, room_id), :snapshot, @snapshot_timeout)
  end

  def join_participant(room_authority, %JoinParticipant{} = command) do
    GenServer.call(room_authority, {:join_participant, command}, @snapshot_timeout)
  end

  @impl true
  def init(options) do
    command = Keyword.fetch!(options, :command)
    incarnation_id = Keyword.fetch!(options, :incarnation_id)

    {:ok,
     %{
       participant_monitors: %{},
       participant_ids: MapSet.new(),
       snapshot: build_snapshot(command, incarnation_id)
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state.snapshot, state}

  def handle_call({:join_participant, command}, _from, state) do
    if MapSet.member?(state.participant_ids, command.participant_id) do
      {:reply, {:error, participant_already_exists(command.participant_id)}, state}
    else
      admit_participant(command, state)
    end
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    {participant_id, participant_monitors} = Map.pop(state.participant_monitors, monitor)

    state = %{
      state
      | participant_monitors: participant_monitors,
        participant_ids: MapSet.delete(state.participant_ids, participant_id)
    }

    {:noreply, state}
  end

  defp admit_participant(command, state) do
    case RoomParticipantSupervisor.start_participant(state.snapshot.incarnation_id, command) do
      {:ok, participant_authority, participant} ->
        monitor = Process.monitor(participant_authority)

        state = %{
          state
          | participant_monitors:
              Map.put(state.participant_monitors, monitor, command.participant_id),
            participant_ids: MapSet.put(state.participant_ids, command.participant_id)
        }

        {:reply, {:ok, participant}, state}

      {:error, :participant_already_exists} ->
        {:reply, {:error, participant_already_exists(command.participant_id)}, state}

      {:error, _reason} ->
        {:reply,
         {:error,
          Vxpipe.CallEngine.Error.new(
            :room_start_failed,
            "The participant could not be admitted.",
            retryable: true
          )}, state}
    end
  end

  defp participant_already_exists(participant_id) do
    Vxpipe.CallEngine.Error.new(
      :participant_already_exists,
      "The participant already exists.",
      details: %{"participant_id" => participant_id}
    )
  end

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
