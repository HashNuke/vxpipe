defmodule Vxpipe.CallEngine.RoomTransferSupervisor do
  @moduledoc false

  alias Vxpipe.CallEngine.RoomAuthority.AgentTransfer
  alias Vxpipe.CallEngine.RoomAuthority.AgentTransfer.Runtime
  alias Vxpipe.CallEngine.ResolvedCallPlan.Participant
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
          [Vxpipe.AgentRuntime.Message.t()]
        ) ::
          {:ok, Task.t()} | {:error, :unavailable}
  def prepare(
        incarnation_id,
        %Request{} = request,
        %Runtime{} = runtime,
        %Participant{} = destination,
        initial_messages
      )
      when is_list(initial_messages) do
    task =
      Task.Supervisor.async_nolink(
        via(incarnation_id),
        AgentTransfer.DestinationPreparer,
        :prepare,
        [request, runtime, destination, initial_messages]
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
