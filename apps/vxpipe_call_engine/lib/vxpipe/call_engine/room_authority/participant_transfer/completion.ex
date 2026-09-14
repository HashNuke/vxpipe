defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Completion do
  @moduledoc false

  alias Vxpipe.CallEngine.Event.ToolCallCompleted
  alias Vxpipe.CallEngine.Id
  alias Vxpipe.CallEngine.RoomAuthority.{EventPublisher, FirstMessage, State}
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.{History, Pending, Phase, Progress}
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  @spec finish(Pending.t(), map(), State.t()) :: State.t()
  def finish(%Pending{} = pending, result, %State{} = state) do
    case Phase.finish(pending) do
      :ok ->
        Progress.publish(pending, :completed, [], state)
        state = History.completed(state, pending.request)
        state = publish(pending.request, result, state)
        GenServer.reply(pending.from, {:ok, result})
        start_first_message(state, pending.request.caller_participant_id)

      {:error, _reason} ->
        Progress.publish(pending, :failed, [], state, :destination_commit_unavailable)
        GenServer.reply(pending.from, {:error, :unavailable})
        exit(:shutdown)
    end
  end

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

  defp start_first_message(state, caller_participant_id) do
    case FirstMessage.start(state) do
      {:ok, state} -> state
      {:error, _error} -> %{state | first_message: FirstMessage.completed(caller_participant_id)}
    end
  end
end
