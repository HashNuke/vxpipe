defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantLifecycle do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.Recorder, as: ArchiveRecorder

  alias Vxpipe.CallEngine.{
    Error,
    ParticipantSupervisor,
    RoomCapabilitySupervisor,
    RoomParticipantSupervisor
  }

  alias Vxpipe.CallEngine.RoomAuthority.{ParticipantPreparation, State, TextCapability}

  @spec join(struct(), State.t()) :: {:reply, {:ok, struct()} | {:error, Error.t()}, State.t()}
  def join(command, %State{} = state) do
    if MapSet.member?(state.participant_ids, command.participant_id) do
      {:reply, {:error, already_exists(command.participant_id)}, state}
    else
      admit(command, state)
    end
  end

  @spec start(struct(), State.t(), keyword()) ::
          {:ok, struct(), State.t()} | {:error, term()}
  def start(command, %State{} = state, options \\ []) do
    with {:ok, preparation} <- prepare(command, state, options) do
      commit(preparation, state)
    end
  end

  @spec prepare(struct(), State.t(), keyword()) ::
          {:ok, ParticipantPreparation.t()} | {:error, term()}
  def prepare(command, state_or_incarnation_id, options \\ [])

  def prepare(command, %State{} = state, options) do
    prepare(command, state.snapshot.incarnation_id, options)
  end

  @spec prepare(struct(), String.t(), keyword()) ::
          {:ok, ParticipantPreparation.t()} | {:error, term()}
  def prepare(command, incarnation_id, options)
      when is_binary(incarnation_id) and is_list(options) do
    case RoomParticipantSupervisor.start_participant(
           incarnation_id,
           command,
           options
         ) do
      {:ok, participant_supervisor, participant} ->
        {:ok,
         %ParticipantPreparation{
           participant_supervisor: participant_supervisor,
           snapshot: participant,
           activation_id: activation_id(options)
         }}

      error ->
        error
    end
  end

  @spec commit(ParticipantPreparation.t(), State.t()) ::
          {:ok, struct(), State.t()} | {:error, :participant_unavailable}
  def commit(%ParticipantPreparation{} = preparation, %State{} = state) do
    participant = preparation.snapshot
    participant_supervisor = preparation.participant_supervisor
    monitor = Process.monitor(participant_supervisor)

    if ParticipantSupervisor.registered?(
         participant.tenant_id,
         participant.room_id,
         participant.participant_id,
         participant_supervisor
       ) do
      commit_available(preparation, participant, monitor, state)
    else
      Process.demonitor(monitor, [:flush])
      {:error, :participant_unavailable}
    end
  end

  defp commit_available(preparation, participant, monitor, state) do
    participant_supervisor = preparation.participant_supervisor

    state = %{
      state
      | activated_agent_participant_ids:
          remember_agent_activation(state.activated_agent_participant_ids, participant),
        participant_monitors:
          Map.put(state.participant_monitors, monitor, participant.participant_id),
        participant_supervisors:
          Map.put(
            state.participant_supervisors,
            participant.participant_id,
            participant_supervisor
          ),
        participant_ids: MapSet.put(state.participant_ids, participant.participant_id),
        participant_roles:
          Map.put(state.participant_roles, participant.participant_id, participant.role)
    }

    archive_recorder =
      state.archive_recorder
      |> ArchiveRecorder.bind_participant_activation(
        participant.participant_id,
        preparation.activation_id
      )
      |> ArchiveRecorder.participant_joined(participant)

    {:ok, participant, %{state | archive_recorder: archive_recorder}}
  end

  @spec discard(ParticipantPreparation.t(), State.t()) :: :ok | {:error, term()}
  def discard(%ParticipantPreparation{} = preparation, %State{} = state) do
    discard(preparation, state.snapshot.incarnation_id)
  end

  @spec discard(ParticipantPreparation.t(), String.t()) :: :ok | {:error, term()}
  def discard(%ParticipantPreparation{} = preparation, incarnation_id)
      when is_binary(incarnation_id) do
    RoomParticipantSupervisor.stop_participant(
      incarnation_id,
      preparation.participant_supervisor
    )
  end

  @spec remove(reference(), term(), State.t()) :: State.t()
  def remove(monitor, reason, %State{} = state) do
    {participant_id, participant_monitors} = Map.pop(state.participant_monitors, monitor)

    affected_connections =
      Map.filter(state.connections, fn {_connection_id, connection} ->
        connection.participant_id == participant_id
      end)

    notify_connections(affected_connections, :participant_unavailable)

    if state.text_capability != nil and
         state.text_capability.participant_id == participant_id do
      notify_connections(state.connections, :agent_unavailable)
      TextCapability.stop(state)
    end

    if state.text_to_speech_capability != nil and
         state.text_to_speech_capability.participant_id == participant_id do
      _ =
        RoomCapabilitySupervisor.stop_capability(
          state.snapshot.incarnation_id,
          state.text_to_speech_capability.pid
        )
    end

    state = %{
      state
      | participant_monitors: participant_monitors,
        participant_supervisors: Map.delete(state.participant_supervisors, participant_id),
        participant_ids: MapSet.delete(state.participant_ids, participant_id),
        participant_roles: Map.delete(state.participant_roles, participant_id)
    }

    archive_recorder =
      ArchiveRecorder.participant_left(state.archive_recorder, participant_id, reason)

    %{state | archive_recorder: archive_recorder}
  end

  defp admit(command, state) do
    case start(command, state) do
      {:ok, participant, state} ->
        {:reply, {:ok, participant}, state}

      {:error, :participant_already_exists} ->
        {:reply, {:error, already_exists(command.participant_id)}, state}

      {:error, _reason} ->
        {:reply,
         {:error,
          Error.new(
            :room_start_failed,
            "The participant could not be admitted.",
            retryable: true
          )}, state}
    end
  end

  defp notify_connections(connections, reason) do
    Enum.each(connections, fn {_connection_id, connection} ->
      send(connection.pid, {:vxpipe_connection_unavailable, reason})
    end)
  end

  defp remember_agent_activation(participant_ids, %{role: :agent, participant_id: participant_id}) do
    MapSet.put(participant_ids, participant_id)
  end

  defp remember_agent_activation(participant_ids, _participant), do: participant_ids

  defp activation_id(options) do
    case Keyword.get(options, :agent_activation) do
      activation when is_list(activation) -> Keyword.get(activation, :activation_id)
      _none -> nil
    end
  end

  defp already_exists(participant_id) do
    Error.new(
      :participant_already_exists,
      "The participant already exists.",
      details: %{"participant_id" => participant_id}
    )
  end
end
