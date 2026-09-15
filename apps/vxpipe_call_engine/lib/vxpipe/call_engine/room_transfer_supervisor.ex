defmodule Vxpipe.CallEngine.RoomTransferSupervisor do
  @moduledoc false

  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Phase
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Runtime
  alias Vxpipe.CallEngine.ResolvedCallPlan.Participant
  alias Vxpipe.CallEngine.{TextToSpeechRuntime, RoomAuthority.Startup}
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  @maximum_tasks_per_room 4
  @recovery_timeout_ms 750

  def start_link(options) do
    incarnation_id = Keyword.fetch!(options, :incarnation_id)

    Task.Supervisor.start_link(
      name: via(incarnation_id),
      max_children: @maximum_tasks_per_room
    )
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :incarnation_id)},
      start: {__MODULE__, :start_link, [options]},
      type: :supervisor
    }
  end

  @spec prepare(
          String.t(),
          Request.t(),
          Runtime.t(),
          Participant.t(),
          boolean(),
          [Vxpipe.AgentRuntime.Message.t()],
          nil | TextToSpeechRuntime.t(),
          %{attempt_id: String.t(), deadline_ms: integer()}
        ) ::
          {:ok, Task.t()} | {:error, :unavailable}
  def prepare(
        incarnation_id,
        %Request{} = request,
        %Runtime{} = runtime,
        %Participant{} = destination,
        first_activation?,
        initial_messages,
        source_text_to_speech,
        %{attempt_id: attempt_id, deadline_ms: deadline_ms}
      )
      when is_boolean(first_activation?) and is_list(initial_messages) and
             is_integer(deadline_ms) do
    scope = %{
      authority: self(),
      incarnation_id: incarnation_id,
      attempt_id: attempt_id,
      deadline_ms: deadline_ms,
      audience_request: request
    }

    task =
      Task.Supervisor.async_nolink(via(incarnation_id), fn ->
        Phase.run(scope, fn ->
          ParticipantTransfer.DestinationPreparer.prepare(
            request,
            runtime,
            destination,
            first_activation?,
            initial_messages,
            source_text_to_speech,
            deadline_ms
          )
        end)
      end)

    send(task.pid, {:vxpipe_transfer_phase_start, task.ref})

    {:ok, task}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec terminate(String.t(), pid()) :: :ok | {:error, :unavailable}
  def terminate(incarnation_id, task) when is_pid(task) do
    case Task.Supervisor.terminate_child(via(incarnation_id), task) do
      :ok -> Vxpipe.CallEngine.Telemetry.transfer_worker_stop(:cancelled)
      {:error, :not_found} -> :ok
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def handoff(incarnation_id, work) when is_function(work, 0) do
    Task.Supervisor.async(via(incarnation_id), work)
  end

  def recover(pending, %Runtime{} = runtime, restore_speech?) when is_boolean(restore_speech?) do
    deadline =
      System.monotonic_time(:millisecond) + @recovery_timeout_ms

    scope = %{
      authority: self(),
      incarnation_id: pending.request.incarnation_id,
      attempt_id: pending.attempt_id,
      deadline_ms: deadline
    }

    task =
      Task.Supervisor.async_nolink(via(scope.incarnation_id), fn ->
        Phase.run(scope, fn ->
          with {:ok, source_text_to_speech} <-
                 recovery_speech(runtime, pending.request, restore_speech?),
               {:ok, capability} <-
                 Startup.prepare_text_to_speech(
                   source_text_to_speech,
                   pending.request.source_participant_id,
                   scope.incarnation_id,
                   scope.authority
                 ) do
            {:handoff, :recover, %{request: pending.request, text_to_speech: capability}}
          end
        end)
      end)

    send(task.pid, {:vxpipe_transfer_phase_start, task.ref})
    {:ok, task, deadline}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp recovery_speech(_runtime, _request, false), do: {:ok, nil}

  defp recovery_speech(runtime, request, true),
    do: Runtime.source_text_to_speech(runtime, request)

  defp via(incarnation_id) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {:transfer_supervisor, incarnation_id}}}
  end
end
