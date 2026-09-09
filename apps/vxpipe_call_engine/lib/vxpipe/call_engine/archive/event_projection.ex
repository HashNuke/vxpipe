defmodule Vxpipe.CallEngine.Archive.EventProjection do
  @moduledoc false

  alias Vxpipe.CallEngine.Event.{
    AgentSpeechProgressed,
    AgentSpeechStarted,
    AgentTurnCompleted,
    AgentTurnFailed,
    AgentTurnInterrupted,
    ParticipantTranscription,
    ParticipantTurnCompleted,
    ParticipantTurnStarted,
    TextOutput,
    ToolCallCancelled,
    ToolCallCompleted,
    ToolCallFailed,
    ToolCallStarted
  }

  @spec project(struct()) :: :ignore | {atom(), keyword()}
  def project(%ParticipantTurnStarted{} = event) do
    {:participant_turn_started,
     common(event,
       participant_id: event.participant_id,
       connection_id: event.connection_id,
       command_id: event.command_id,
       correlation_id: event.correlation_id,
       payload: %{"modality" => event.modality}
     )}
  end

  def project(%ParticipantTurnCompleted{} = event) do
    {:participant_turn_completed,
     common(event,
       participant_id: event.participant_id,
       connection_id: event.connection_id,
       command_id: event.command_id,
       correlation_id: event.correlation_id,
       payload: %{"modality" => event.modality}
     )}
  end

  def project(%ParticipantTranscription{final: false}), do: :ignore

  def project(%ParticipantTranscription{} = event) do
    {:participant_transcription_final,
     common(event,
       participant_id: event.participant_id,
       connection_id: event.connection_id,
       command_id: event.command_id,
       correlation_id: event.correlation_id,
       payload: %{
         "final" => true,
         "provider_turn_index" => event.provider_turn_index,
         "text" => event.text
       }
     )}
  end

  def project(%TextOutput{} = event) do
    {:agent_output_generated,
     common(event,
       participant_id: event.participant_id,
       source_participant_id: event.source_participant_id,
       connection_id: event.connection_id,
       command_id: event.command_id,
       correlation_id: event.correlation_id,
       payload: %{
         "aggregated_by" => event.aggregated_by,
         "text" => event.text,
         "will_be_spoken" => event.will_be_spoken
       }
     )}
  end

  def project(%ToolCallStarted{} = event) do
    {:tool_call_started,
     tool_common(event,
       payload: %{"arguments" => event.arguments, "name" => event.name}
     )}
  end

  def project(%ToolCallCompleted{} = event) do
    {:tool_call_completed,
     tool_common(event,
       payload: %{"name" => event.name, "result" => event.result}
     )}
  end

  def project(%ToolCallFailed{} = event) do
    {:tool_call_failed,
     tool_common(event,
       payload: %{"name" => event.name, "reason" => event.reason}
     )}
  end

  def project(%ToolCallCancelled{} = event) do
    {:tool_call_cancelled,
     tool_common(event,
       payload: %{"name" => event.name}
     )}
  end

  def project(%AgentSpeechStarted{} = event) do
    {:agent_output_delivery_started, agent_common(event, payload: %{})}
  end

  def project(%AgentSpeechProgressed{} = event) do
    {:agent_output_delivery_progressed,
     agent_common(event,
       payload: %{"played_ms" => event.played_ms, "total_ms" => event.total_ms}
     )}
  end

  def project(%AgentTurnCompleted{} = event) do
    {:agent_turn_completed, agent_common(event, payload: %{})}
  end

  def project(%AgentTurnFailed{} = event) do
    {:agent_turn_failed,
     agent_common(event,
       payload: %{"reason" => event.reason, "retryable" => event.retryable}
     )}
  end

  def project(%AgentTurnInterrupted{} = event) do
    {:agent_turn_interrupted,
     agent_common(event,
       payload: %{
         "interrupted_by_connection_id" => event.interrupted_by_connection_id,
         "interrupted_by_participant_id" => event.interrupted_by_participant_id,
         "interruption_command_id" => event.interruption_command_id,
         "interruption_correlation_id" => event.interruption_correlation_id,
         "played_ms" => event.played_ms
       }
     )}
  end

  defp common(event, attributes) do
    [
      id: event.id,
      public_sequence: event.sequence,
      occurred_at: event.occurred_at
    ] ++ attributes
  end

  defp agent_common(event, attributes) do
    common(
      event,
      [
        participant_id: event.participant_id,
        source_participant_id: event.source_participant_id,
        connection_id: event.connection_id,
        command_id: event.command_id,
        correlation_id: event.correlation_id
      ] ++ attributes
    )
  end

  defp tool_common(event, attributes) do
    agent_common(event, [tool_call_id: event.tool_call_id] ++ attributes)
  end
end
