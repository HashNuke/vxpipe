defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantLifecycle do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.Recorder, as: ArchiveRecorder
  alias Vxpipe.CallEngine.{Error, RoomCapabilitySupervisor, RoomParticipantSupervisor}
  alias Vxpipe.CallEngine.RoomAuthority.{State, TextCapability}

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
    case RoomParticipantSupervisor.start_participant(
           state.snapshot.incarnation_id,
           command,
           options
         ) do
      {:ok, participant_supervisor, participant} ->
        monitor = Process.monitor(participant_supervisor)

        state = %{
          state
          | participant_monitors:
              Map.put(state.participant_monitors, monitor, command.participant_id),
            participant_ids: MapSet.put(state.participant_ids, command.participant_id),
            participant_roles:
              Map.put(state.participant_roles, command.participant_id, participant.role)
        }

        archive_recorder =
          ArchiveRecorder.participant_joined(state.archive_recorder, participant)

        {:ok, participant, %{state | archive_recorder: archive_recorder}}

      error ->
        error
    end
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

  defp already_exists(participant_id) do
    Error.new(
      :participant_already_exists,
      "The participant already exists.",
      details: %{"participant_id" => participant_id}
    )
  end
end
