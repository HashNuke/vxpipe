defmodule Vxpipe.CallEngine.RoomParticipantSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Vxpipe.CallEngine.Command.JoinParticipant
  alias Vxpipe.CallEngine.ParticipantSupervisor

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

  def start_participant(incarnation_id, %JoinParticipant{} = command, options \\ []) do
    participant_options =
      options
      |> Keyword.take([:agent_activation])
      |> Keyword.merge(command: command, incarnation_id: incarnation_id)

    case DynamicSupervisor.start_child(
           via(incarnation_id),
           {ParticipantSupervisor, participant_options}
         ) do
      {:ok, participant_supervisor} ->
        participant_authority = ParticipantSupervisor.authority(participant_supervisor)

        {:ok, participant_supervisor,
         Vxpipe.CallEngine.ParticipantAuthority.snapshot(participant_authority)}

      {:error, {:already_started, _pid}} ->
        {:error, :participant_already_exists}

      {:error, {:shutdown, {:failed_to_start_child, _child, {:already_started, _pid}}}} ->
        {:error, :participant_already_exists}

      {:error, reason} ->
        if already_started?(reason),
          do: {:error, :participant_already_exists},
          else: {:error, reason}
    end
  end

  def stop_participant(incarnation_id, participant_supervisor)
      when is_pid(participant_supervisor) do
    DynamicSupervisor.terminate_child(via(incarnation_id), participant_supervisor)
  end

  defp already_started?({:already_started, pid}) when is_pid(pid), do: true

  defp already_started?(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.any?(&already_started?/1)
  end

  defp already_started?(_value), do: false

  defp via(incarnation_id) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {:participant_supervisor, incarnation_id}}}
  end
end
