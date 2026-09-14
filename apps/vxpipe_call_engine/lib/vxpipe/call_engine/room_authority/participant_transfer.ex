defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer do
  @moduledoc false

  alias Vxpipe.CallEngine.RoomParticipantSupervisor
  alias Vxpipe.CallEngine.RoomTransferSupervisor
  alias Vxpipe.CallEngine.Command.{AttachConnection, ParticipantTransferControl}
  alias Vxpipe.CallEngine.TextToSpeechRequest
  alias Vxpipe.CallEngine.Tool.Context
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  alias Vxpipe.CallEngine.RoomAuthority.{SpokenHistory, State}

  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.{
    Authorizer,
    Cleanup,
    DestinationParticipant,
    History,
    HumanHandoff,
    HumanPreparation,
    Pending,
    Preparation
  }

  @spec begin(Request.t(), GenServer.from(), State.t()) ::
          {:noreply, State.t()} | {:reply, {:error, :rejected | :unavailable}, State.t()}
  def begin(%Request{} = request, from, %State{pending_participant_transfer: nil} = state) do
    with :ok <- Authorizer.authorize(request, state) do
      timeout_ms = state.participant_transfer_runtime.plan.transfer_policy.attempt_timeout_ms
      deadline_ms = System.monotonic_time(:millisecond) + timeout_ms
      start_preparation(request, from, deadline_ms, state)
    else
      {:error, :rejected} -> {:reply, {:error, :rejected}, state}
    end
  end

  def begin(%Request{}, _from, %State{} = state) do
    {:reply, {:error, :rejected}, state}
  end

  defp start_preparation(request, from, deadline_ms, state) do
    attempt_id = Vxpipe.CallEngine.Id.generate(:transfer_attempt)

    destination =
      Map.fetch!(
        state.participant_transfer_runtime.plan.participants,
        request.destination_definition_key
      )

    initial_messages = projected_history(state.spoken_history, destination)

    previously_activated? =
      MapSet.member?(state.activated_agent_participant_ids, destination.participant_id)

    destination = DestinationParticipant.materialize(destination, previously_activated?)
    state = History.started(state, request)

    case RoomTransferSupervisor.prepare(
           request.incarnation_id,
           request,
           state.participant_transfer_runtime,
           destination,
           not previously_activated?,
           initial_messages,
           state.text_to_speech_runtime,
           %{attempt_id: attempt_id, deadline_ms: deadline_ms}
         ) do
      {:ok, task} ->
        remaining_ms = max(deadline_ms - System.monotonic_time(:millisecond), 0)

        timer =
          Process.send_after(
            self(),
            {:vxpipe_participant_transfer_deadline, task.ref},
            remaining_ms
          )

        pending = %Pending{
          attempt_id: attempt_id,
          deadline_ms: deadline_ms,
          from: from,
          request: request,
          task: task,
          timer: timer
        }

        held =
          MapSet.new(state.connections, fn {_id, connection} -> connection.participant_id end)

        {:noreply, %{state | pending_participant_transfer: pending, held_participant_ids: held}}

      {:error, :unavailable} ->
        state = History.failed(state, request, :preparation_supervisor_unavailable)
        {:reply, {:error, :unavailable}, state}
    end
  end

  @spec attach_connection(
          AttachConnection.t(),
          pid(),
          pid(),
          pid() | nil,
          reference(),
          State.t()
        ) ::
          :unhandled
          | {:handled, {:reply, tuple() | {:error, Vxpipe.CallEngine.Error.t()}, State.t()}}
  def attach_connection(command, caller, subscriber, output_sink, room_monitor, %State{} = state) do
    HumanHandoff.attach_connection(
      command,
      caller,
      subscriber,
      output_sink,
      room_monitor,
      state
    )
  end

  @spec control(ParticipantTransferControl.t(), pid(), State.t()) ::
          {:reply, :ok | {:error, Vxpipe.CallEngine.Error.t()}, State.t()}
  def control(%ParticipantTransferControl{} = command, caller, %State{} = state) do
    HumanHandoff.control(command, caller, state)
  end

  def progress(
        reference,
        progress,
        %State{pending_participant_transfer: %Pending{task: %Task{ref: reference}} = pending} =
          state
      ) do
    Enum.each(state.connections, fn {_id, connection} ->
      if connection.transfer_attempt_id == pending.attempt_id do
        send(connection.pid, {:vxpipe_transfer_progress, pending.attempt_id, progress})
      end
    end)

    {:noreply, state}
  end

  def progress(_reference, _progress, state), do: {:noreply, state}

  @spec prepared(reference(), Preparation.t(), State.t()) :: {:noreply, State.t()}
  def prepared(
        reference,
        %Preparation{} = preparation,
        %State{pending_participant_transfer: %Pending{task: %Task{ref: reference}} = pending} =
          state
      ) do
    cond do
      deadline_elapsed?(pending) ->
        HumanHandoff.failed(%{pending | preparation: preparation}, :deadline_elapsed, state)

      Authorizer.authorize(pending.request, state) != :ok ->
        HumanHandoff.failed(
          %{pending | preparation: preparation},
          :source_authority_changed,
          state
        )

      true ->
        HumanHandoff.prepared(pending, preparation, state)
    end
  end

  @spec prepared(reference(), HumanPreparation.t(), State.t()) :: {:noreply, State.t()}
  def prepared(
        reference,
        %HumanPreparation{} = preparation,
        %State{pending_participant_transfer: %Pending{task: %Task{ref: reference}} = pending} =
          state
      ) do
    cond do
      deadline_elapsed?(pending) ->
        pending = %{pending | preparation: preparation}
        HumanHandoff.failed(pending, :deadline_elapsed, state)

      Authorizer.authorize(pending.request, state) != :ok ->
        pending = %{pending | preparation: preparation}
        HumanHandoff.failed(pending, :source_authority_changed, state)

      true ->
        HumanHandoff.prepared(pending, preparation, state)
    end
  end

  def prepared(_reference, %Preparation{} = preparation, %State{} = state) do
    Cleanup.discard(preparation, state)
    {:noreply, state}
  end

  def prepared(_reference, %HumanPreparation{} = preparation, %State{} = state) do
    Cleanup.discard(preparation, state)
    {:noreply, state}
  end

  @spec playback(pid(), TextToSpeechRequest.t(), atom() | tuple(), State.t()) ::
          :unhandled | {:handled, {:noreply, State.t()}}
  def playback(capability, %TextToSpeechRequest{} = request, status, %State{} = state) do
    HumanHandoff.playback(capability, request, status, state)
  end

  @spec text_to_speech_unavailable(pid(), State.t()) ::
          :unhandled | {:handled, {:noreply, State.t()}}
  def text_to_speech_unavailable(capability, %State{} = state) do
    HumanHandoff.unavailable(capability, state)
  end

  def speech_to_text_unavailable(capability, identity, %State{} = state) do
    HumanHandoff.speech_to_text_unavailable(capability, identity, state)
  end

  @spec worker_failed(reference(), History.failure_cause(), State.t()) ::
          {:noreply, State.t()}
  def worker_failed(
        reference,
        reason,
        %State{pending_participant_transfer: %Pending{task: %Task{ref: reference}} = pending} =
          state
      ) do
    HumanHandoff.failed(pending, reason, state)
  end

  def worker_failed(_reference, _reason, state), do: {:noreply, state}

  @spec deadline_elapsed(reference(), State.t()) :: {:noreply, State.t()}
  def deadline_elapsed(
        reference,
        %State{pending_participant_transfer: %Pending{task: %Task{ref: reference}} = pending} =
          state
      ) do
    HumanHandoff.deadline(pending, state)
  end

  def deadline_elapsed(_reference, %State{} = state), do: {:noreply, state}

  @spec worker_down(reference(), term(), State.t()) :: {:handled, State.t()} | :unhandled
  def worker_down(
        reference,
        _reason,
        %State{pending_participant_transfer: %Pending{task: %Task{ref: reference}}} =
          state
      ) do
    {:noreply, state} = worker_failed(reference, :preparation_process_down, state)
    {:handled, state}
  end

  def worker_down(reference, _reason, %State{} = state) do
    HumanHandoff.capability_down(reference, state)
  end

  @spec connection_down(String.t(), State.t()) :: :unhandled | {:handled, State.t()}
  def connection_down(connection_id, %State{} = state) do
    HumanHandoff.connection_down(connection_id, state)
  end

  @spec teardown_source(State.t(), pid(), Context.t()) :: State.t()
  def teardown_source(%State{} = state, capability, %Context{} = context)
      when is_pid(capability) do
    case Map.pop(state.pending_agent_teardowns, capability) do
      {%{participant_id: participant_id, participant_supervisor: supervisor}, pending}
      when participant_id == context.agent_participant_id ->
        _ =
          RoomParticipantSupervisor.stop_participant(
            state.snapshot.incarnation_id,
            supervisor
          )

        %{state | pending_agent_teardowns: pending}

      {_missing_or_stale, _pending} ->
        state
    end
  end

  @spec promote_connection_after_source_exit(State.t(), String.t()) :: State.t()
  def promote_connection_after_source_exit(%State{} = state, participant_id)
      when is_binary(participant_id) do
    case Map.pop(state.pending_connection_promotions, participant_id) do
      {%{attachment: attachment, attempt_id: attempt_id, connection: connection}, pending} ->
        send(connection, {:vxpipe_transfer_main_media, attempt_id, attachment})
        %{state | pending_connection_promotions: pending}

      {nil, _pending} ->
        state
    end
  end

  defp deadline_elapsed?(pending) do
    System.monotonic_time(:millisecond) >= pending.deadline_ms
  end

  defp projected_history(spoken_history, %{kind: :agent, transfer_history: transfer_history}) do
    SpokenHistory.project(spoken_history, transfer_history)
  end

  defp projected_history(_spoken_history, %{kind: :human}), do: []
end
