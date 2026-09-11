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
    RoomMixer,
    TranscriptRouter,
    RoomTransferSupervisor,
    RoomParticipantSupervisor
  }

  alias Vxpipe.CallEngine.MediaPolicy.Authority, as: MediaPolicyAuthority
  alias Vxpipe.CallEngine.RoomIncarnationSupervisor.RecordingChildren

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
    {options, recording_children} = RecordingChildren.prepare(options)
    participant_supervisor = {RoomParticipantSupervisor, options}
    capability_supervisor = {RoomCapabilitySupervisor, options}
    transfer_supervisor = {RoomTransferSupervisor, options}

    authority = %{
      id: RoomAuthority,
      start: {RoomAuthority, :start_link, [options]},
      restart: :temporary,
      significant: true
    }

    children =
      [participant_supervisor, capability_supervisor, transfer_supervisor] ++
        live_inspection_child(options) ++
        call_variables_child(options) ++
        call_lifecycle_child(options) ++
        media_policy_child(options) ++
        transcript_router_child(options) ++
        room_mixer_child(options) ++ [authority] ++ recording_children

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

  defp media_policy_child(options) do
    case Keyword.get(options, :plan) do
      %ResolvedCallPlan{} -> [{MediaPolicyAuthority, options}]
      nil -> []
    end
  end

  defp room_mixer_child(options) do
    case Keyword.get(options, :plan) do
      %ResolvedCallPlan{} = plan ->
        mixer_options =
          options
          |> Keyword.fetch!(:room_mixer)
          |> Keyword.merge(
            tenant_id: plan.tenant_id,
            room_id: plan.room_id,
            incarnation_id: Keyword.fetch!(options, :incarnation_id)
          )

        child = Supervisor.child_spec({RoomMixer, mixer_options}, [])
        [Map.put(child, :significant, true)]

      nil ->
        []
    end
  end

  defp transcript_router_child(options) do
    case Keyword.get(options, :plan) do
      %ResolvedCallPlan{} = plan ->
        router_options =
          options
          |> Keyword.fetch!(:transcript_router)
          |> Keyword.merge(
            tenant_id: plan.tenant_id,
            room_id: plan.room_id,
            incarnation_id: Keyword.fetch!(options, :incarnation_id)
          )

        child =
          Supervisor.child_spec(
            {TranscriptRouter, router_options},
            []
          )

        [Map.put(child, :significant, true)]

      nil ->
        []
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
