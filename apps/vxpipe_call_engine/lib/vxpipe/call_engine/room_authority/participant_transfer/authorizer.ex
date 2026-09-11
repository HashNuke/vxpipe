defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Authorizer do
  @moduledoc false

  alias Vxpipe.CallEngine.RoomAuthority.State
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Runtime
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  @spec authorize(Request.t(), State.t()) :: :ok | {:error, :rejected}
  def authorize(
        %Request{} = request,
        %State{participant_transfer_runtime: %Runtime{} = runtime} = state
      ) do
    source = Map.get(runtime.plan.participants, request.source_definition_key)
    destination = Map.get(runtime.plan.participants, request.destination_definition_key)
    connection = Map.get(state.connections, request.connection_id)

    if state.snapshot.tenant_id == request.tenant_id and
         state.snapshot.room_id == request.room_id and
         state.snapshot.incarnation_id == request.incarnation_id and
         state.text_capability != nil and
         state.text_capability.participant_id == request.source_participant_id and
         state.text_capability.activation_id == request.source_activation_id and
         GenServer.whereis(state.text_capability.pid) == request.source_capability and
         source != nil and source.kind == :agent and
         source.participant_id == request.source_participant_id and
         request.destination_definition_key in source.transfers and
         destination != nil and destination.kind == :agent and
         destination.participant_id == request.destination_participant_id and
         not MapSet.member?(state.participant_ids, request.destination_participant_id) and
         connection != nil and connection.participant_id == request.caller_participant_id do
      :ok
    else
      {:error, :rejected}
    end
  end

  def authorize(%Request{}, %State{}), do: {:error, :rejected}
end
