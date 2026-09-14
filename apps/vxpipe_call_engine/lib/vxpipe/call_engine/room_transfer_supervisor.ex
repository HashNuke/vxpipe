defmodule Vxpipe.CallEngine.RoomTransferSupervisor do
  @moduledoc false

  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Cleanup
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Phase
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Runtime
  alias Vxpipe.CallEngine.ResolvedCallPlan.Participant
  alias Vxpipe.CallEngine.{TextToSpeechRuntime, RoomAuthority.Startup}
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  @maximum_tasks_per_room 4

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
      audience_request: if(destination.kind == :human, do: request)
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

  @spec restore_text_to_speech(
          String.t(),
          TextToSpeechRuntime.t(),
          String.t(),
          pid()
        ) :: {:ok, Task.t()} | {:error, :unavailable}
  def restore_text_to_speech(
        incarnation_id,
        %TextToSpeechRuntime{} = runtime,
        participant_id,
        owner
      )
      when is_binary(incarnation_id) and is_binary(participant_id) and is_pid(owner) do
    task =
      Task.Supervisor.async_nolink(
        via(incarnation_id),
        Startup,
        :prepare_text_to_speech,
        [runtime, participant_id, incarnation_id, owner]
      )

    {:ok, task}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  @spec cleanup_destination(Request.t(), pid()) :: :ok | {:error, :unavailable}
  def cleanup_destination(%Request{} = request, task) when is_pid(task) do
    start_cleanup(request.incarnation_id, fn ->
      _ = terminate(request.incarnation_id, task)
      Cleanup.discard_destination(request)
    end)
  end

  @spec cleanup_restoration(Request.t(), pid()) :: :ok | {:error, :unavailable}
  def cleanup_restoration(%Request{} = request, task) when is_pid(task) do
    start_cleanup(request.incarnation_id, fn ->
      _ = terminate(request.incarnation_id, task)
      Cleanup.discard_source_text_to_speech(request)
    end)
  end

  @spec terminate(String.t(), pid()) :: :ok | {:error, :unavailable}
  def terminate(incarnation_id, task) when is_pid(task) do
    case Task.Supervisor.terminate_child(via(incarnation_id), task) do
      :ok -> :ok
      {:error, :not_found} -> :ok
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  def handoff(incarnation_id, work) when is_function(work, 0) do
    Task.Supervisor.async(via(incarnation_id), work)
  end

  def recover(pending) do
    deadline =
      System.monotonic_time(:millisecond) + ParticipantTransfer.SourceRestorer.timeout_ms()

    scope = %{
      authority: self(),
      incarnation_id: pending.request.incarnation_id,
      attempt_id: pending.attempt_id,
      deadline_ms: deadline
    }

    task =
      Task.Supervisor.async_nolink(via(scope.incarnation_id), fn ->
        Phase.run(scope, fn -> {:handoff, :recover, pending.request} end)
      end)

    send(task.pid, {:vxpipe_transfer_phase_start, task.ref})
    {:ok, task, deadline}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp start_cleanup(incarnation_id, cleanup) when is_function(cleanup, 0) do
    case Task.Supervisor.start_child(via(incarnation_id), cleanup) do
      {:ok, _task} -> :ok
      {:error, _reason} -> {:error, :unavailable}
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp via(incarnation_id) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {:transfer_supervisor, incarnation_id}}}
  end
end
