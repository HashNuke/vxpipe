defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Completion do
  @moduledoc false

  alias Vxpipe.CallEngine.Event.ToolCallCompleted
  alias Vxpipe.CallEngine.Id
  alias Vxpipe.CallEngine.RoomAuthority.{EventPublisher, State}
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  @spec result(Request.t()) :: map()
  def result(%Request{} = request) do
    %{
      "destination" => request.destination_definition_key,
      "status" => "completed"
    }
  end

  @spec publish(Request.t(), map(), State.t()) :: State.t()
  def publish(%Request{} = request, result, %State{} = state) when is_map(result) do
    connection = Map.fetch!(state.connections, request.connection_id)

    event = %ToolCallCompleted{
      id: Id.generate(:event),
      sequence: state.next_sequence,
      tenant_id: request.tenant_id,
      room_id: request.room_id,
      incarnation_id: request.incarnation_id,
      participant_id: request.source_participant_id,
      source_participant_id: request.caller_participant_id,
      connection_id: request.connection_id,
      command_id: request.command_id,
      correlation_id: request.correlation_id,
      tool_call_id: request.tool_call_id,
      name: "transfer",
      result: result,
      occurred_at: DateTime.utc_now(:millisecond)
    }

    state
    |> EventPublisher.publish(connection.pid, event)
    |> Map.update!(:background_tool_calls, &Map.delete(&1, request.tool_call_id))
    |> Map.update!(:next_sequence, &(&1 + 1))
  end
end
