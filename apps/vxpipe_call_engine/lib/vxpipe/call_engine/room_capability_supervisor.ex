defmodule Vxpipe.CallEngine.RoomCapabilitySupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Vxpipe.CallEngine.Capability.{DeterministicText, SpeechToText}
  alias Vxpipe.CallEngine.Command.AttachConnection
  alias Vxpipe.CallEngine.Media.Ingress

  def start_link(options) do
    incarnation_id = Keyword.fetch!(options, :incarnation_id)
    DynamicSupervisor.start_link(__MODULE__, :ok, name: via(incarnation_id))
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :incarnation_id)},
      start: {__MODULE__, :start_link, [options]},
      type: :supervisor
    }
  end

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  def start_capability(incarnation_id, room_authority, participant_id) do
    options = [room_authority: room_authority, participant_id: participant_id]
    DynamicSupervisor.start_child(via(incarnation_id), {DeterministicText, options})
  end

  def start_speech_to_text(
        incarnation_id,
        room_authority,
        %AttachConnection{} = command,
        provider,
        transport,
        media_ingress_options
      ) do
    identity = [
      tenant_id: command.tenant_id,
      room_id: command.room_id,
      incarnation_id: command.incarnation_id,
      participant_id: command.participant_id,
      connection_id: command.connection_id
    ]

    capability_options =
      identity ++
        [
          owner: room_authority,
          provider: provider,
          transport: transport
        ]

    case DynamicSupervisor.start_child(
           via(incarnation_id),
           {SpeechToText, capability_options}
         ) do
      {:ok, capability} ->
        case DynamicSupervisor.start_child(
               via(incarnation_id),
               {Ingress,
                identity ++
                  [capability: capability] ++ media_ingress_options}
             ) do
          {:ok, ingress} ->
            {:ok, capability, ingress}

          {:error, _reason} = error ->
            _ = DynamicSupervisor.terminate_child(via(incarnation_id), capability)
            error
        end

      {:error, _reason} = error ->
        error
    end
  end

  def stop_capability(incarnation_id, capability) do
    DynamicSupervisor.terminate_child(via(incarnation_id), capability)
  end

  def stop_speech_to_text(incarnation_id, capability, ingress) do
    _ = DynamicSupervisor.terminate_child(via(incarnation_id), ingress)
    _ = DynamicSupervisor.terminate_child(via(incarnation_id), capability)
    :ok
  end

  defp via(incarnation_id) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {:capability_supervisor, incarnation_id}}}
  end
end
