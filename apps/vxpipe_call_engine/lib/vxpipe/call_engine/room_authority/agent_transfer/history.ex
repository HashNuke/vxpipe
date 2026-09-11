defmodule Vxpipe.CallEngine.RoomAuthority.AgentTransfer.History do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.Recorder
  alias Vxpipe.CallEngine.Id
  alias Vxpipe.CallEngine.RoomAuthority.State
  alias Vxpipe.CallEngine.Tool.ParticipantTransfer.Request

  @failure_causes [
    :deadline_elapsed,
    :destination_participant_unavailable,
    :destination_plan_unavailable,
    :destination_text_to_speech_unavailable,
    :preparation_process_down,
    :preparation_supervisor_unavailable,
    :source_authority_changed
  ]

  @type failure_cause ::
          :deadline_elapsed
          | :destination_participant_unavailable
          | :destination_plan_unavailable
          | :destination_text_to_speech_unavailable
          | :preparation_process_down
          | :preparation_supervisor_unavailable
          | :source_authority_changed

  @spec started(State.t(), Request.t()) :: State.t()
  def started(%State{} = state, %Request{} = request) do
    record(state, :participant_transfer_started, request, identity_payload(request))
  end

  @spec completed(State.t(), Request.t()) :: State.t()
  def completed(%State{} = state, %Request{} = request) do
    record(
      state,
      :participant_transfer_completed,
      request,
      Map.put(identity_payload(request), "outcome", "completed")
    )
  end

  @spec failed(State.t(), Request.t(), failure_cause()) :: State.t()
  def failed(%State{} = state, %Request{} = request, cause) do
    payload =
      request
      |> identity_payload()
      |> Map.put("cause", cause |> normalize_cause() |> Atom.to_string())
      |> Map.put("outcome", "failed")

    record(state, :participant_transfer_failed, request, payload)
  end

  defp record(state, kind, request, payload) do
    archive_recorder =
      Recorder.internal_fact(state.archive_recorder, kind,
        id: Id.generate(:event),
        participant_id: request.source_participant_id,
        activation_id: request.source_activation_id,
        source_participant_id: request.caller_participant_id,
        connection_id: request.connection_id,
        command_id: request.command_id,
        correlation_id: request.correlation_id,
        tool_call_id: request.tool_call_id,
        occurred_at: DateTime.utc_now(:millisecond),
        payload: payload
      )

    %{state | archive_recorder: archive_recorder}
  end

  defp identity_payload(request) do
    %{
      "destination_definition_key" => request.destination_definition_key,
      "destination_participant_id" => request.destination_participant_id,
      "source_definition_key" => request.source_definition_key
    }
  end

  defp normalize_cause(cause) when cause in @failure_causes, do: cause
  defp normalize_cause(_cause), do: :preparation_process_down
end
