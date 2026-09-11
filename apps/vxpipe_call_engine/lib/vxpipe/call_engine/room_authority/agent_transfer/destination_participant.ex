defmodule Vxpipe.CallEngine.RoomAuthority.AgentTransfer.DestinationParticipant do
  @moduledoc false

  alias Vxpipe.CallEngine.Id
  alias Vxpipe.CallEngine.ResolvedCallPlan.{Participant, ToolBinding}
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Binding

  @spec materialize(Participant.t(), boolean()) :: Participant.t()
  def materialize(%Participant{} = participant, false), do: participant

  def materialize(%Participant{kind: :agent} = participant, true) do
    activation_id = Id.generate(:activation)

    %{
      participant
      | activation_id: activation_id,
        tools: rebind_transfer_tools(participant.tools, activation_id)
    }
  end

  defp rebind_transfer_tools(tools, activation_id) do
    Map.new(tools, fn
      {name, %ToolBinding{type: :participant_transfer, transfer: %Binding{} = binding} = tool} ->
        {name, %{tool | transfer: %{binding | source_activation_id: activation_id}}}

      entry ->
        entry
    end)
  end
end
