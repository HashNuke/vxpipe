defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.HumanHandoff do
  @moduledoc false

  alias Vxpipe.CallEngine.Command.{AttachConnection, ParticipantTransferControl}
  alias Vxpipe.CallEngine.{Error, TextToSpeechRequest}

  alias Vxpipe.CallEngine.RoomAuthority.{ConnectionLifecycle, Startup, State}

  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.{
    Authorizer,
    Cleanup,
    Committer,
    History,
    HumanBriefing,
    HumanCommitter,
    HumanPreparation,
    Pending,
    Phase,
    Preparation,
    Progress,
    PrivateSpeech
  }

  @spec prepared(Pending.t(), HumanPreparation.t() | Preparation.t(), State.t()) ::
          {:noreply, State.t()}
  def prepared(%Pending{} = pending, %HumanPreparation{} = preparation, %State{} = state) do
    preparation = %{
      preparation
      | outbound_leg_monitor: monitor_outbound_leg(preparation.outbound_leg),
        text_to_speech: Startup.activate_text_to_speech(preparation.text_to_speech)
    }

    pending = %{pending | briefing: :waiting, preparation: preparation}
    {:ok, state} = progress(pending, state)
    {:noreply, state}
  end

  def prepared(%Pending{} = pending, %Preparation{} = preparation, %State{} = state) do
    preparation = %{
      preparation
      | text_to_speech: Startup.activate_text_to_speech(preparation.text_to_speech)
    }

    :ok =
      Phase.handoff(pending.task.pid, :prepare, %{
        request: pending.request,
        preparation: preparation
      })

    pending = %{pending | preparation: preparation, handoff: :preparing}
    {:noreply, %{state | pending_participant_transfer: pending}}
  end

  @spec attach_connection(
          AttachConnection.t(),
          pid(),
          pid(),
          pid() | nil,
          reference(),
          State.t()
        ) :: :unhandled | {:handled, {:reply, tuple() | {:error, Error.t()}, State.t()}}
  def attach_connection(
        %AttachConnection{} = command,
        caller,
        subscriber,
        output_sink,
        room_monitor,
        %State{pending_participant_transfer: %Pending{} = pending} = state
      ) do
    if human_pending?(pending, state) do
      if pending_destination?(command, pending) and not deadline_elapsed?(pending) do
        reply =
          ConnectionLifecycle.attach_transfer_preparation(
            command,
            caller,
            subscriber,
            output_sink,
            room_monitor,
            pending.attempt_id,
            state
          )

        case reply do
          {:reply,
           {:ok, _role, _runtime, :transfer_preparation, _input, _output, _attempt} = response,
           state} ->
            pending = %{pending | destination_connection_id: command.connection_id}
            {:handled, {:reply, response, %{state | pending_participant_transfer: pending}}}

          other ->
            {:handled, other}
        end
      else
        {:handled, {:reply, {:error, rejected_control()}, state}}
      end
    else
      :unhandled
    end
  end

  def attach_connection(
        %AttachConnection{},
        _caller,
        _subscriber,
        _output_sink,
        _room_monitor,
        %State{}
      ),
      do: :unhandled

  @spec control(ParticipantTransferControl.t(), pid(), State.t()) ::
          {:reply, :ok | {:error, Error.t()}, State.t()}
  def control(
        %ParticipantTransferControl{} = command,
        caller,
        %State{pending_participant_transfer: %Pending{} = pending} = state
      ) do
    with true <- human_pending?(pending, state),
         :ok <- authorize_control(command, caller, pending, state),
         {:ok, pending} <- apply_control(command.action, pending),
         {:ok, state} <- progress(pending, state) do
      {:reply, :ok, state}
    else
      {:error, %Error{} = error} -> {:reply, {:error, error}, state}
      _not_pending_or_duplicate -> {:reply, {:error, rejected_control()}, state}
    end
  end

  def control(%ParticipantTransferControl{}, _caller, %State{} = state) do
    {:reply, {:error, rejected_control()}, state}
  end

  @spec playback(pid(), TextToSpeechRequest.t(), atom() | tuple(), State.t()) ::
          :unhandled | {:handled, {:noreply, State.t()}}
  def playback(
        capability,
        %TextToSpeechRequest{purpose: :transfer_briefing} = request,
        status,
        %State{pending_participant_transfer: %Pending{} = pending} = state
      ) do
    if HumanBriefing.matches?(pending, capability, request) do
      state =
        case status do
          :completed when pending.briefing != :completed ->
            pending = HumanBriefing.complete(pending, state)
            notify_acceptance_ready(pending, state)
            {:ok, state} = progress(pending, state)
            state

          _started_or_progress ->
            state
        end

      {:handled, {:noreply, state}}
    else
      :unhandled
    end
  end

  def playback(_capability, %TextToSpeechRequest{}, _status, %State{}), do: :unhandled

  @spec unavailable(pid(), State.t()) :: :unhandled | {:handled, {:noreply, State.t()}}
  def unavailable(
        capability,
        %State{
          pending_participant_transfer:
            %Pending{preparation: %HumanPreparation{} = prep} = pending
        } =
          state
      ) do
    if prep.text_to_speech != nil and prep.text_to_speech.pid == capability do
      {:handled, {:noreply, fail(pending, :destination_text_to_speech_unavailable, state)}}
    else
      :unhandled
    end
  end

  def unavailable(_capability, %State{}), do: :unhandled

  def speech_to_text_unavailable(
        capability,
        identity,
        %State{pending_participant_transfer: %Pending{} = pending} = state
      ) do
    if PrivateSpeech.matches?(pending, capability, identity, state),
      do: {:handled, {:noreply, fail(pending, :destination_speech_to_text_unavailable, state)}},
      else: :unhandled
  end

  def speech_to_text_unavailable(_capability, _identity, %State{}), do: :unhandled

  @spec capability_down(reference(), State.t()) :: :unhandled | {:handled, State.t()}
  def capability_down(
        monitor,
        %State{
          pending_participant_transfer:
            %Pending{preparation: %HumanPreparation{} = prep} = pending
        } =
          state
      ) do
    cond do
      prep.text_to_speech != nil and prep.text_to_speech.monitor == monitor ->
        {:handled, fail(pending, :destination_text_to_speech_unavailable, state)}

      prep.outbound_leg_monitor == monitor ->
        {:handled, fail(pending, :destination_connection_unavailable, state)}

      PrivateSpeech.monitor?(pending, monitor, state) ->
        {:handled, fail(pending, :destination_speech_to_text_unavailable, state)}

      true ->
        :unhandled
    end
  end

  def capability_down(_monitor, %State{}), do: :unhandled

  @spec deadline(Pending.t(), State.t()) :: {:noreply, State.t()}
  def deadline(%Pending{} = pending, %State{} = state) do
    {:noreply, fail(pending, :deadline_elapsed, state)}
  end

  @spec failed(Pending.t(), atom(), State.t()) :: {:noreply, State.t()}
  def failed(%Pending{} = pending, cause, %State{} = state) when is_atom(cause) do
    {:noreply, fail(pending, cause, state)}
  end

  @spec connection_down(String.t(), State.t()) :: :unhandled | {:handled, State.t()}
  def connection_down(
        connection_id,
        %State{pending_participant_transfer: %Pending{} = pending} = state
      )
      when is_binary(connection_id) do
    if human_pending?(pending, state) and pending.destination_connection_id == connection_id do
      {:handled, fail(pending, :destination_connection_unavailable, state)}
    else
      :unhandled
    end
  end

  def connection_down(_connection_id, %State{}), do: :unhandled

  defp apply_control(:accept, %Pending{accepted?: false, briefing: :completed} = pending),
    do: {:ok, %{pending | accepted?: true}}

  defp apply_control(:accept, %Pending{accepted?: false}) do
    {:error, Error.new(:participant_transfer_not_ready, "The private briefing has not finished.")}
  end

  defp apply_control(:media_ready, %Pending{media_ready?: false} = pending),
    do: {:ok, %{pending | media_ready?: true}}

  defp apply_control(_action, _pending), do: {:error, :duplicate}

  defp notify_acceptance_ready(pending, state) do
    Enum.each(state.connections, fn {_id, connection} ->
      if connection.transfer_attempt_id == pending.attempt_id do
        send(connection.pid, {:vxpipe_transfer_acceptance_ready, pending.attempt_id})
      end
    end)
  end

  defp progress(%Pending{media_ready?: true, briefing: :waiting} = pending, state) do
    connection = transfer_connection(pending.attempt_id, state)

    case connection do
      %{output_sink: output_sink} when is_pid(output_sink) ->
        case HumanBriefing.start(pending, pending.preparation, connection, state) do
          {:ok, request} ->
            pending = %{pending | briefing: :playing, briefing_request: request}
            {:ok, %{state | pending_participant_transfer: pending}}

          {:error, :unavailable} ->
            {:ok, fail(pending, :destination_text_to_speech_unavailable, state)}
        end

      _missing_connection ->
        {:error, rejected_control()}
    end
  end

  defp progress(%Pending{accepted?: true, briefing: :completed} = pending, state) do
    cond do
      Authorizer.authorize(pending.request, state) != :ok ->
        {:ok, fail(pending, :source_authority_changed, state)}

      pending.handoff != nil ->
        {:ok, %{state | pending_participant_transfer: pending}}

      true ->
        :ok =
          Phase.handoff(pending.task.pid, :prepare, %{
            request: pending.request,
            preparation: pending.preparation
          })

        held =
          MapSet.new(state.connections, fn {_id, connection} -> connection.participant_id end)

        {:ok,
         %{
           state
           | pending_participant_transfer: %{pending | handoff: :preparing},
             held_participant_ids: held
         }}
    end
  end

  defp progress(%Pending{} = pending, state) do
    {:ok, %{state | pending_participant_transfer: pending}}
  end

  def handoff_result(
        reference,
        stage,
        result,
        %State{pending_participant_transfer: %Pending{task: %Task{ref: reference}} = pending} =
          state
      ) do
    case {stage, pending.handoff, result} do
      {_, %{stage: :recovering, failure: _cause}, _result} ->
        recovery_failed(pending, state)

      {_, %{stage: :releasing, failure: _cause}, _result} ->
        release_failed(pending, state)

      {:recover, %{stage: :recovering, deadline_ms: deadline, cause: cause}, {:ok, recovered}} ->
        with :ok <- Authorizer.authorize(pending.request, state),
             :ok <- Phase.finish(%{pending | deadline_ms: deadline}) do
          state = record_output_generation(state, recovered)
          state = restore_text_to_speech(state, recovered.text_to_speech)
          state = History.failed(state, pending.request, cause, :completed)
          Progress.publish(pending, :recovered, [], state)
          GenServer.reply(pending.from, {:error, :unavailable})

          {:noreply,
           %{state | pending_participant_transfer: nil, held_participant_ids: MapSet.new()}}
        else
          _failure -> recovery_failed(pending, state)
        end

      {_, %{stage: :recovering}, _failure} ->
        recovery_failed(pending, state)

      {:prepare, :preparing, {:ok, ready}} ->
        with :ok <- Authorizer.authorize(pending.request, state),
             {:ok, current} <- Vxpipe.CallEngine.RoomAuthority.ReadinessBinding.capture(state),
             true <- current == ready.graph.inventory.binding,
             {:ok, state} <- HumanCommitter.commit_ready(pending, ready, state) do
          :ok = Phase.handoff(pending.task.pid, :release, ready)

          {:noreply,
           %{
             state
             | pending_participant_transfer: %{
                 pending
                 | handoff: %{stage: :releasing, ready: ready}
               }
           }}
        else
          false ->
            retry_preparation(pending, ready, state)

          {:error, :stale_candidate} ->
            retry_preparation(pending, ready, state)

          _commit_failed ->
            Progress.publish(pending, :failed, [], state)
            GenServer.reply(pending.from, {:error, :unavailable})
            {:stop, :handoff_commit_failed, state}
        end

      {:release, %{stage: :releasing}, {:ok, ready}} ->
        with :ok <- validate_release(ready, state) do
          demonitor_outbound_leg(pending.preparation)
          state = record_output_generation(state, ready)

          state =
            case pending.preparation do
              %Preparation{} -> Committer.finish_ready(pending, state)
              %HumanPreparation{} -> HumanCommitter.finish_ready(pending, ready, state)
            end

          {:noreply, state}
        else
          _changed -> release_failed(pending, state)
        end

      {_, %{stage: :releasing}, _failure} ->
        release_failed(pending, state)

      {_, _, {:error, _reason}} ->
        {:noreply, fail(pending, :destination_media_unavailable, state)}

      _stale ->
        {:noreply, state}
    end
  end

  def handoff_result(_reference, _stage, _result, state), do: {:noreply, state}

  defp validate_release(ready, state) do
    with {:ok, current} <- Vxpipe.CallEngine.RoomAuthority.ReadinessBinding.capture(state),
         true <- current == ready.release_inventory.binding do
      Vxpipe.CallEngine.MediaPolicy.Authority.validate_candidate(
        state.media_policy_authority,
        ready.release_inventory.candidate
      )
    else
      _changed -> {:error, :handoff_changed}
    end
  catch
    :exit, _reason -> {:error, :handoff_unavailable}
  end

  defp release_failed(pending, state) do
    Phase.cancel(pending)
    Progress.publish(pending, :failed, [], state)
    GenServer.reply(pending.from, {:error, :unavailable})
    cause = Map.get(pending.handoff, :failure, :destination_media_unavailable)
    state = History.failed(state, pending.request, cause, :failed)
    {:stop, :handoff_release_failed, state}
  end

  defp record_output_generation(state, released) do
    connections =
      Enum.reduce(released.connections, state.connections, fn {id, _binding}, connections ->
        Map.update!(connections, id, &Map.put(&1, :output_generation, released.scope.generation))
      end)

    %{state | connections: connections}
  end

  defp restore_text_to_speech(state, nil), do: state

  defp restore_text_to_speech(state, capability),
    do: %{state | text_to_speech_capability: Startup.activate_text_to_speech(capability)}

  defp retry_preparation(pending, ready, state) do
    if deadline_elapsed?(pending) do
      {:noreply, fail(pending, :destination_media_unavailable, state)}
    else
      :ok = Phase.handoff(pending.task.pid, :prepare, %{request: pending.request, ready: ready})
      {:noreply, state}
    end
  end

  defp authorize_control(command, caller, pending, state) do
    connection = Map.get(state.connections, command.connection_id)

    if not deadline_elapsed?(pending) and
         command.tenant_id == pending.request.tenant_id and
         command.room_id == pending.request.room_id and
         command.incarnation_id == pending.request.incarnation_id and
         command.participant_id == pending.request.destination_participant_id and
         command.attempt_id == pending.attempt_id and connection != nil and
         connection.pid == caller and connection.actor_id == command.actor_id and
         connection.participant_id == command.participant_id and
         connection.admission == :transfer_preparation and
         connection.transfer_attempt_id == command.attempt_id do
      :ok
    else
      {:error, rejected_control()}
    end
  end

  defp pending_destination?(command, pending) do
    command.tenant_id == pending.request.tenant_id and
      command.room_id == pending.request.room_id and
      command.incarnation_id == pending.request.incarnation_id and
      command.participant_id == pending.request.destination_participant_id
  end

  defp human_pending?(pending, state) do
    case Map.get(
           state.participant_transfer_runtime.plan.participants,
           pending.request.destination_definition_key
         ) do
      %{
        kind: :human,
        connection: %{service: :web, mode: :receive, admission: :transfer}
      } ->
        true

      %{
        kind: :human,
        connection: %{service: service, mode: :dial, admission: :transfer}
      }
      when is_binary(service) ->
        true

      _other ->
        false
    end
  end

  defp transfer_connection(attempt_id, state) do
    Enum.find_value(state.connections, fn {_connection_id, connection} ->
      if connection.transfer_attempt_id == attempt_id, do: connection
    end)
  end

  defp fail(%Pending{handoff: %{stage: stage}} = pending, cause, state)
       when stage in [:recovering, :releasing] do
    # Latch cancellation before returning to the mailbox: a successful worker result
    # may already be queued ahead of the failure notification sent below.
    pending = %{pending | handoff: Map.put_new(pending.handoff, :failure, cause)}
    worker_stage = if stage == :recovering, do: :recover, else: :release

    send(
      self(),
      {:vxpipe_transfer_handoff_result, pending.task.ref, worker_stage, {:error, cause}}
    )

    %{state | pending_participant_transfer: pending}
  end

  defp fail(pending, cause, state) do
    Phase.cancel(pending)
    discard_preparation(pending, state)
    Cleanup.discard_destination(pending.request)
    state = ConnectionLifecycle.discard_transfer(pending.attempt_id, :transfer_failed, state)

    if MapSet.size(state.held_participant_ids) > 0 do
      start_recovery(pending, cause, state)
    else
      state = History.failed(state, pending.request, cause, :not_required)
      Progress.publish(pending, :recovered, [], state)
      GenServer.reply(pending.from, {:error, :unavailable})
      %{state | pending_participant_transfer: nil}
    end
  end

  defp start_recovery(pending, cause, state) do
    Progress.publish(pending, :recovering, [], state)

    source_text_to_speech =
      if state.text_to_speech_capability == nil, do: state.text_to_speech_runtime

    case Vxpipe.CallEngine.RoomTransferSupervisor.recover(pending, source_text_to_speech) do
      {:ok, task, deadline} ->
        timer =
          Process.send_after(
            self(),
            {:vxpipe_participant_transfer_deadline, task.ref},
            max(deadline - System.monotonic_time(:millisecond), 0)
          )

        pending = %{
          pending
          | task: task,
            timer: timer,
            preparation: nil,
            handoff: %{stage: :recovering, cause: cause, deadline_ms: deadline}
        }

        %{state | pending_participant_transfer: pending}

      {:error, _reason} ->
        pending = %{pending | handoff: %{stage: :recovering, cause: cause}}
        fail(pending, :recovery_failed, %{state | pending_participant_transfer: pending})
    end
  end

  defp recovery_failed(pending, state) do
    Phase.cancel(pending)
    Progress.publish(pending, :failed, [], state)
    GenServer.reply(pending.from, {:error, :unavailable})

    outcome =
      if System.monotonic_time(:millisecond) >= Map.get(pending.handoff, :deadline_ms, :infinity),
        do: :timed_out,
        else: :failed

    state = History.failed(state, pending.request, pending.handoff.cause, outcome)
    {:stop, :handoff_recovery_failed, state}
  end

  defp discard_preparation(%Pending{preparation: %HumanPreparation{} = preparation}, state) do
    demonitor_outbound_leg(preparation)
    _ = Cleanup.discard(preparation, state)
    :ok
  end

  defp discard_preparation(%Pending{preparation: %Preparation{} = preparation}, state),
    do: Cleanup.discard(preparation, state)

  defp discard_preparation(%Pending{} = pending, _state) do
    Cleanup.discard_destination(pending.request)
  end

  defp deadline_elapsed?(pending) do
    System.monotonic_time(:millisecond) >= pending.deadline_ms
  end

  defp monitor_outbound_leg(nil), do: nil
  defp monitor_outbound_leg(outbound_leg), do: Process.monitor(outbound_leg.owner)

  defp demonitor_outbound_leg(%HumanPreparation{outbound_leg_monitor: nil}), do: :ok
  defp demonitor_outbound_leg(%Preparation{}), do: :ok

  defp demonitor_outbound_leg(%HumanPreparation{outbound_leg_monitor: monitor}) do
    Process.demonitor(monitor, [:flush])
    :ok
  end

  defp rejected_control do
    Error.new(
      :participant_transfer_rejected,
      "The participant transfer control was rejected."
    )
  end
end
