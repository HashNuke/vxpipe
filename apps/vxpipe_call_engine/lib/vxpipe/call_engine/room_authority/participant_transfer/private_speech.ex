defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.PrivateSpeech do
  @moduledoc false

  alias Vxpipe.CallEngine.{Error, RoomCapabilitySupervisor, SpeechToTextRuntime}
  alias Vxpipe.CallEngine.MediaPolicy.{Authority, SpeechToTextDemand}
  alias Vxpipe.CallEngine.RoomAuthority.{ConnectionLifecycle, State}

  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.{
    Authorizer,
    HumanPreparation,
    Pending
  }

  def bound?(pending, state), do: binding(pending, state) != nil

  def monitor?(pending, monitor, state) do
    case binding(pending, state) do
      nil -> false
      speech -> monitor in [speech.capability_monitor, speech.ingress_monitor]
    end
  end

  def matches?(pending, capability, identity, state) do
    case ConnectionLifecycle.authorized_speech_to_text(capability, identity, state) do
      {:ok, connection_id, connection} ->
        connection_id == pending.destination_connection_id and
          admission_matches?(pending, connection.admission)

      _other ->
        false
    end
  end

  defp binding(pending, state) do
    case Map.get(state.connections, pending.destination_connection_id) do
      %{admission: admission, speech_to_text: speech} ->
        if admission_matches?(pending, admission), do: speech

      _missing ->
        nil
    end
  end

  defp admission_matches?(_pending, :transfer_preparation), do: true
  defp admission_matches?(%Pending{handoff: %{stage: :releasing}}, :main), do: true
  defp admission_matches?(_pending, _admission), do: false

  def allocate(command, caller, attempt_id, %State{} = state) do
    with {:ok, pending, _connection} <- authorize(command, caller, attempt_id, state) do
      start(command, pending, state)
    else
      :error -> {:reply, {:error, rejected()}, state}
    end
  end

  defp authorize(command, caller, attempt_id, state) do
    with %Pending{attempt_id: ^attempt_id, preparation: %HumanPreparation{}} = pending <-
           state.pending_participant_transfer,
         %{admission: :transfer_preparation, transfer_attempt_id: ^attempt_id} = connection <-
           Map.get(state.connections, command.connection_id),
         true <- command.tenant_id == state.snapshot.tenant_id,
         true <- command.room_id == state.snapshot.room_id,
         true <- command.incarnation_id == state.snapshot.incarnation_id,
         true <- command.actor_id == connection.actor_id,
         true <- command.participant_id == connection.participant_id,
         true <- command.participant_id == pending.request.destination_participant_id,
         true <- command.connection_id == pending.destination_connection_id,
         true <- caller == connection.pid,
         true <- DateTime.compare(command.deadline, DateTime.utc_now()) == :gt,
         true <- remaining_ms(pending) > 0 and Process.alive?(pending.task.pid),
         :ok <- Authorizer.authorize(pending.request, state) do
      {:ok, pending, connection}
    else
      _invalid -> :error
    end
  end

  defp start(command, pending, state) do
    case pending.preparation.destination.speech_to_text do
      nil -> clear(command, state)
      %SpeechToTextRuntime{} = runtime -> start_selected(command, pending, runtime, state)
    end
  end

  defp start_selected(command, pending, runtime, state) do
    base = Authority.snapshot(state.media_policy_authority, max(remaining_ms(pending), 1))

    present =
      base.present_participant_ids
      |> MapSet.delete(pending.request.source_participant_id)
      |> MapSet.put(pending.request.destination_participant_id)

    with {:ok, candidate} <-
           Authority.preview_presence(
             state.media_policy_authority,
             present,
             max(remaining_ms(pending), 1)
           ) do
      if SpeechToTextDemand.required?(
           candidate.snapshot,
           command.participant_id,
           runtime.activity_agent_id
         ),
         do: ensure_pair(command, pending, runtime, state, base),
         else: clear(command, state)
    else
      _unavailable -> {:reply, {:error, unavailable()}, state}
    end
  catch
    :exit, _reason -> {:reply, {:error, unavailable()}, state}
  end

  defp clear(command, state) do
    state = ConnectionLifecycle.clear_private_speech_to_text(command.connection_id, state)
    {:reply, {:ok, nil}, state}
  end

  defp ensure_pair(command, pending, runtime, state, base) do
    case binding(pending, state) do
      nil -> allocate_pair(command, pending, runtime, state, base)
      speech -> {:reply, {:ok, Map.take(speech, [:capability, :ingress])}, state}
    end
  end

  defp allocate_pair(command, pending, runtime, state, base) do
    usage = [
      call_id: runtime.call_id,
      participant_id: runtime.participant_id,
      activation_id: runtime.activation_id,
      provider: runtime.usage_provider
    ]

    options = [
      provider_private: runtime.provider_private,
      initial_policy: base,
      preparation: [
        owner: pending.task.pid,
        attempt_id: pending.attempt_id,
        deadline_ms: pending.deadline_ms
      ]
    ]

    case RoomCapabilitySupervisor.start_speech_to_text(
           command.incarnation_id,
           self(),
           command,
           runtime.provider,
           Keyword.put(runtime.media_ingress, :input_admission, :closed),
           usage,
           options
         ) do
      {:ok, capability, ingress} ->
        bind_pair(command, pending, base, capability, ingress, state)

      {:error, _reason} ->
        {:reply, {:error, unavailable()}, state}
    end
  catch
    :exit, _reason -> {:reply, {:error, unavailable()}, state}
  end

  defp bind_pair(command, pending, _base, capability, ingress, state) do
    scope = %{
      owner: pending.task.pid,
      attempt_id: pending.attempt_id,
      deadline_ms: pending.deadline_ms,
      participant_id: command.participant_id
    }

    connection = Map.fetch!(state.connections, command.connection_id).pid

    with {:ok, _snapshot} <-
           Authority.register_private_enforcers(
             state.media_policy_authority,
             [ingress, capability],
             connection,
             scope,
             remaining_ms(pending)
           ),
         {:reply, :ok, state} <-
           ConnectionLifecycle.bind_private_speech_to_text(command, capability, ingress, state) do
      {:reply, {:ok, %{capability: capability, ingress: ingress}}, state}
    else
      _error ->
        _ =
          RoomCapabilitySupervisor.stop_speech_to_text(
            command.incarnation_id,
            capability,
            ingress
          )

        {:reply, {:error, unavailable()}, state}
    end
  end

  defp remaining_ms(pending),
    do: min(max(pending.deadline_ms - System.monotonic_time(:millisecond), 0), 1_000)

  defp rejected,
    do:
      Error.new(:participant_transfer_rejected, "The participant transfer control was rejected.")

  defp unavailable,
    do: Error.new(:speech_to_text_unavailable, "Private speech preparation is unavailable.")
end
