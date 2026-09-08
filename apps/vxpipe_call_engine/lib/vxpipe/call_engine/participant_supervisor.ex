defmodule Vxpipe.CallEngine.ParticipantSupervisor do
  @moduledoc false

  use Supervisor

  alias Vxpipe.CallEngine.{AgentActivationSupervisor, ParticipantAuthority}

  def start_link(options) do
    command = Keyword.fetch!(options, :command)

    Supervisor.start_link(__MODULE__, options,
      name: via(command.tenant_id, command.room_id, command.participant_id)
    )
  end

  def child_spec(options) do
    command = Keyword.fetch!(options, :command)

    %{
      id: {__MODULE__, command.participant_id},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      shutdown: :infinity,
      type: :supervisor
    }
  end

  @spec authority(Supervisor.supervisor()) :: pid()
  def authority(supervisor) do
    case Supervisor.which_children(supervisor) do
      children when is_list(children) -> child_pid(children, :authority)
    end
  end

  @impl true
  def init(options) do
    authority =
      options
      |> Keyword.take([:command, :incarnation_id])
      |> then(&Supervisor.child_spec({ParticipantAuthority, &1}, participant_child(:authority)))

    children =
      case Keyword.get(options, :agent_activation) do
        nil ->
          [authority]

        activation_options when is_list(activation_options) ->
          activation =
            Supervisor.child_spec(
              {AgentActivationSupervisor, activation_options},
              participant_child(:agent_activation)
            )

          [authority, activation]
      end

    Supervisor.init(children,
      strategy: :one_for_one,
      auto_shutdown: :any_significant
    )
  end

  defp participant_child(id), do: [id: id, restart: :temporary, significant: true]

  defp child_pid(children, id) do
    case List.keyfind(children, id, 0) do
      {^id, pid, _type, _modules} when is_pid(pid) -> pid
      _missing -> raise "participant child #{inspect(id)} is unavailable"
    end
  end

  defp via(tenant_id, room_id, participant_id) do
    {:via, Registry,
     {Vxpipe.CallEngine.RoomRegistry,
      {:participant_supervisor, tenant_id, room_id, participant_id}}}
  end
end
