defmodule Vxpipe.CallEngine.RoomIncarnationSupervisor do
  @moduledoc false

  use Supervisor

  alias Vxpipe.CallEngine.{
    CallVariables,
    CallLifecycle,
    LiveInspection.Buffer,
    ResolvedCallPlan,
    RoomAuthority,
    RoomCapabilitySupervisor,
    RoomParticipantSupervisor
  }

  def start_link(options), do: Supervisor.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :incarnation_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      shutdown: :infinity,
      type: :supervisor
    }
  end

  @impl true
  def init(options) do
    participant_supervisor = {RoomParticipantSupervisor, options}
    capability_supervisor = {RoomCapabilitySupervisor, options}

    authority = %{
      id: RoomAuthority,
      start: {RoomAuthority, :start_link, [options]},
      restart: :temporary,
      significant: true
    }

    children =
      [participant_supervisor, capability_supervisor] ++
        live_inspection_child(options) ++
        call_variables_child(options) ++ call_lifecycle_child(options) ++ [authority]

    Supervisor.init(children,
      strategy: :one_for_one,
      auto_shutdown: :any_significant
    )
  end

  defp call_variables_child(options) do
    case Keyword.get(options, :plan) do
      %ResolvedCallPlan{} -> [{CallVariables, options}]
      nil -> []
    end
  end

  defp call_lifecycle_child(options) do
    case Keyword.get(options, :plan) do
      %ResolvedCallPlan{} -> [{CallLifecycle, options}]
      nil -> []
    end
  end

  defp live_inspection_child(options) do
    case Keyword.get(options, :plan) do
      %ResolvedCallPlan{} = plan ->
        settings = Keyword.fetch!(options, :live_inspection)

        identity = %{
          tenant_id: plan.tenant_id,
          call_id: plan.call_id,
          room_id: plan.room_id,
          incarnation_id: Keyword.fetch!(options, :incarnation_id)
        }

        [
          {Buffer,
           identity: identity,
           maximum_pending_records: Keyword.fetch!(settings, :maximum_pending_records),
           maximum_retained_records: Keyword.fetch!(settings, :maximum_retained_records)}
        ]

      nil ->
        []
    end
  end
end
