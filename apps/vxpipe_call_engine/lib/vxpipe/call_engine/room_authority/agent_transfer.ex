defmodule Vxpipe.CallEngine.RoomAuthority.AgentTransfer do
  @moduledoc false

  alias Vxpipe.CallEngine.RoomParticipantSupervisor
  alias Vxpipe.CallEngine.RoomTransferSupervisor
  alias Vxpipe.CallEngine.Tool.Context
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  alias Vxpipe.CallEngine.RoomAuthority.{SpokenHistory, Startup, State}

  alias Vxpipe.CallEngine.RoomAuthority.AgentTransfer.{
    Authorizer,
    Cleanup,
    Committer,
    DestinationParticipant,
    History,
    Pending,
    Preparation,
    Restoration,
    SourceRestorer
  }

  @spec begin(Request.t(), GenServer.from(), State.t()) ::
          {:noreply, State.t()} | {:reply, {:error, :rejected | :unavailable}, State.t()}
  def begin(%Request{} = request, from, %State{pending_agent_transfer: nil} = state) do
    with :ok <- Authorizer.authorize(request, state) do
      timeout_ms = state.agent_transfer_runtime.plan.transfer_policy.attempt_timeout_ms
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
    destination =
      Map.fetch!(
        state.agent_transfer_runtime.plan.participants,
        request.destination_definition_key
      )

    initial_messages =
      SpokenHistory.project(state.spoken_history, destination.transfer_history)

    previously_activated? =
      MapSet.member?(state.activated_agent_participant_ids, destination.participant_id)

    destination = DestinationParticipant.materialize(destination, previously_activated?)
    state = History.started(state, request)

    case RoomTransferSupervisor.prepare(
           request.incarnation_id,
           request,
           state.agent_transfer_runtime,
           destination,
           not previously_activated?,
           initial_messages
         ) do
      {:ok, task} ->
        remaining_ms = max(deadline_ms - System.monotonic_time(:millisecond), 0)

        timer =
          Process.send_after(
            self(),
            {:vxpipe_agent_transfer_deadline, task.ref},
            remaining_ms
          )

        pending = %Pending{
          deadline_ms: deadline_ms,
          from: from,
          request: request,
          task: task,
          timer: timer
        }

        {:noreply, %{state | pending_agent_transfer: pending}}

      {:error, :unavailable} ->
        state = History.failed(state, request, :preparation_supervisor_unavailable)
        {:reply, {:error, :unavailable}, state}
    end
  end

  @spec prepared(reference(), Preparation.t(), State.t()) :: {:noreply, State.t()}
  def prepared(
        reference,
        %Preparation{} = preparation,
        %State{pending_agent_transfer: %Pending{task: %Task{ref: reference}} = pending} = state
      ) do
    settle_task(pending)

    cond do
      deadline_elapsed?(pending) ->
        Cleanup.discard(preparation, state)
        restore_or_fail(pending, :deadline_elapsed, state)

      Authorizer.authorize(pending.request, state) != :ok ->
        Cleanup.discard(preparation, state)

        reject_pending(pending, :source_authority_changed, %{
          state
          | pending_agent_transfer: nil
        })

      true ->
        commit_prepared(pending, preparation, state)
    end
  end

  def prepared(_reference, %Preparation{} = preparation, %State{} = state) do
    Cleanup.discard(preparation, state)
    {:noreply, state}
  end

  @spec worker_failed(reference(), History.failure_cause(), State.t()) ::
          {:noreply, State.t()}
  def worker_failed(
        reference,
        reason,
        %State{pending_agent_transfer: %Pending{task: %Task{ref: reference}} = pending} = state
      ) do
    settle_task(pending)
    Cleanup.discard_destination(pending.request)
    restore_or_fail(pending, reason, state)
  end

  def worker_failed(
        reference,
        _reason,
        %State{pending_agent_transfer: %Restoration{task: %Task{ref: reference}} = restoration} =
          state
      ) do
    settle_task(restoration)
    SourceRestorer.cleanup(restoration.request)
    finish_restoration(restoration, :failed, state)
  end

  def worker_failed(_reference, _reason, %State{} = state), do: {:noreply, state}

  @spec deadline_elapsed(reference(), State.t()) :: {:noreply, State.t()}
  def deadline_elapsed(
        reference,
        %State{pending_agent_transfer: %Pending{task: %Task{ref: reference}} = pending} = state
      ) do
    _ = RoomTransferSupervisor.terminate(pending.request.incarnation_id, pending.task.pid)
    Process.demonitor(reference, [:flush])
    cancel_timer(pending.timer)
    Cleanup.discard_destination(pending.request)
    restore_or_fail(pending, :deadline_elapsed, state)
  end

  def deadline_elapsed(_reference, %State{} = state), do: {:noreply, state}

  @spec restored(reference(), map(), State.t()) :: {:noreply, State.t()}
  def restored(
        reference,
        capability,
        %State{pending_agent_transfer: %Restoration{task: %Task{ref: reference}} = restoration} =
          state
      )
      when is_map(capability) do
    settle_task(restoration)
    {outcome, state} = SourceRestorer.activate(capability, restoration.request, state)
    finish_restoration(restoration, outcome, state)
  end

  def restored(_reference, capability, %State{} = state) when is_map(capability) do
    _ = Startup.discard_text_to_speech(capability, state)
    {:noreply, state}
  end

  @spec restoration_deadline_elapsed(reference(), State.t()) :: {:noreply, State.t()}
  def restoration_deadline_elapsed(
        reference,
        %State{pending_agent_transfer: %Restoration{task: %Task{ref: reference}} = restoration} =
          state
      ) do
    _ =
      RoomTransferSupervisor.terminate(
        restoration.request.incarnation_id,
        restoration.task.pid
      )

    Process.demonitor(reference, [:flush])
    cancel_timer(restoration.timer)
    SourceRestorer.cleanup(restoration.request)
    finish_restoration(restoration, :timed_out, state)
  end

  def restoration_deadline_elapsed(_reference, %State{} = state), do: {:noreply, state}

  @spec worker_down(reference(), term(), State.t()) :: {:handled, State.t()} | :unhandled
  def worker_down(
        reference,
        _reason,
        %State{pending_agent_transfer: %Pending{task: %Task{ref: reference}} = pending} = state
      ) do
    cancel_timer(pending.timer)
    Cleanup.discard_destination(pending.request)
    {:noreply, state} = restore_or_fail(pending, :preparation_process_down, state)
    {:handled, state}
  end

  def worker_down(
        reference,
        _reason,
        %State{pending_agent_transfer: %Restoration{task: %Task{ref: reference}} = restoration} =
          state
      ) do
    cancel_timer(restoration.timer)
    SourceRestorer.cleanup(restoration.request)
    {:noreply, state} = finish_restoration(restoration, :failed, state)
    {:handled, state}
  end

  def worker_down(_reference, _reason, %State{}), do: :unhandled

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

  defp commit_prepared(pending, preparation, state) do
    {result, state} = Committer.commit(pending, preparation, state)
    GenServer.reply(pending.from, {:ok, result})
    {:noreply, state}
  end

  defp settle_task(pending) do
    Process.demonitor(pending.task.ref, [:flush])
    cancel_timer(pending.timer)
  end

  defp cancel_timer(timer) do
    _ = Process.cancel_timer(timer)
    :ok
  end

  defp deadline_elapsed?(pending) do
    System.monotonic_time(:millisecond) >= pending.deadline_ms
  end

  defp fail_pending(pending, cause, state) do
    state = History.failed(state, pending.request, cause, :not_required)
    GenServer.reply(pending.from, {:error, :unavailable})
    {:noreply, state}
  end

  defp reject_pending(pending, cause, state) do
    state = History.failed(state, pending.request, cause, :not_required)
    GenServer.reply(pending.from, {:error, :rejected})
    {:noreply, state}
  end

  defp restore_or_fail(pending, cause, state) do
    case SourceRestorer.start(pending.request, pending.from, cause, state) do
      {:ok, restoration} ->
        {:noreply, %{state | pending_agent_transfer: restoration}}

      :not_required ->
        fail_pending(pending, cause, %{state | pending_agent_transfer: nil})

      {:error, :unavailable} ->
        state = History.failed(state, pending.request, cause, :failed)
        GenServer.reply(pending.from, {:error, :unavailable})
        {:noreply, %{state | pending_agent_transfer: nil}}
    end
  end

  defp finish_restoration(restoration, outcome, state) do
    state = History.failed(state, restoration.request, restoration.cause, outcome)
    GenServer.reply(restoration.from, {:error, :unavailable})
    {:noreply, %{state | pending_agent_transfer: nil}}
  end
end
