defmodule Vxpipe.CallEngine.RoomTransferSupervisor do
  @moduledoc false

  alias Vxpipe.CallEngine.RoomAuthority.AgentTransfer
  alias Vxpipe.CallEngine.RoomAuthority.AgentTransfer.Runtime
  alias Vxpipe.CallEngine.ResolvedCallPlan.Participant
  alias Vxpipe.CallEngine.{TextToSpeechRuntime, RoomAuthority.Startup}
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  def start_link(options) do
    incarnation_id = Keyword.fetch!(options, :incarnation_id)
    Task.Supervisor.start_link(name: via(incarnation_id))
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
          [Vxpipe.AgentRuntime.Message.t()]
        ) ::
          {:ok, Task.t()} | {:error, :unavailable}
  def prepare(
        incarnation_id,
        %Request{} = request,
        %Runtime{} = runtime,
        %Participant{} = destination,
        first_activation?,
        initial_messages
      )
      when is_boolean(first_activation?) and is_list(initial_messages) do
    task =
      Task.Supervisor.async_nolink(
        via(incarnation_id),
        AgentTransfer.DestinationPreparer,
        :prepare,
        [request, runtime, destination, first_activation?, initial_messages]
      )

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

  @spec terminate(String.t(), pid()) :: :ok | {:error, :unavailable}
  def terminate(incarnation_id, task) when is_pid(task) do
    case Task.Supervisor.terminate_child(via(incarnation_id), task) do
      :ok -> :ok
      {:error, :not_found} -> :ok
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp via(incarnation_id) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {:transfer_supervisor, incarnation_id}}}
  end
end
