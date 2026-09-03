defmodule Vxpipe.CallEngine.RoomCapabilitySupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Vxpipe.CallEngine.Capability.DeterministicText

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

  def stop_capability(incarnation_id, capability) do
    DynamicSupervisor.terminate_child(via(incarnation_id), capability)
  end

  defp via(incarnation_id) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {:capability_supervisor, incarnation_id}}}
  end
end
