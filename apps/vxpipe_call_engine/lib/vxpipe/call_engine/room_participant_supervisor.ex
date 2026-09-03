defmodule Vxpipe.CallEngine.RoomParticipantSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Vxpipe.CallEngine.Command.JoinParticipant
  alias Vxpipe.CallEngine.ParticipantAuthority

  def start_link(options) do
    incarnation_id = Keyword.fetch!(options, :incarnation_id)
    DynamicSupervisor.start_link(__MODULE__, :ok, name: via(incarnation_id))
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :incarnation_id)},
      start: {__MODULE__, :start_link, [options]},
      type: :supervisor
    }
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  def start_participant(incarnation_id, %JoinParticipant{} = command) do
    options = [command: command, incarnation_id: incarnation_id]

    case DynamicSupervisor.start_child(via(incarnation_id), {ParticipantAuthority, options}) do
      {:ok, participant_authority} ->
        {:ok, participant_authority, ParticipantAuthority.snapshot(participant_authority)}

      {:error, {:already_started, _pid}} ->
        {:error, :participant_already_exists}

      {:error, {:shutdown, {:failed_to_start_child, _child, {:already_started, _pid}}}} ->
        {:error, :participant_already_exists}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp via(incarnation_id) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {:participant_supervisor, incarnation_id}}}
  end
end
