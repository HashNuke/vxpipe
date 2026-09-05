defmodule Vxpipe.Gateway.RTVI.Codec do
  @moduledoc false

  alias Vxpipe.CallEngine.Event.{
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

  @label "rtvi-ai"
  @protocol_version "2.1.0"
  @protocol_major 2

  @type send_text :: %{
          id: String.t(),
          content: String.t(),
          run_immediately: boolean(),
          audio_response: boolean()
        }

  @spec handle(binary()) ::
          :ignore | {:reply, binary()} | {:command, {:send_text, send_text()}}
  def handle(payload) when is_binary(payload) do
    with {:ok, message} when is_map(message) <- JSON.decode(payload) do
      handle_message(message)
    else
      _error -> :ignore
    end
  end

  @spec encode_event(TextOutput.t()) :: {:ok, binary()}
  def encode_event(%TextOutput{} = event) do
    data = %{
      "text" => event.text,
      "aggregated_by" => aggregation(event.aggregated_by),
      "segment_id" => event.sequence,
      "will_be_spoken" => event.will_be_spoken
    }

    data =
      if event.will_be_spoken do
        Map.put(data, "spoken_status", "new")
      else
        data
      end

    {:ok,
     JSON.encode!(%{
       "id" => event.id,
       "label" => @label,
       "type" => "bot-output",
       "data" => data
     })}
  end

  @spec encode_event(ParticipantTranscription.t()) :: {:ok, binary()}
  def encode_event(%ParticipantTranscription{} = event) do
    {:ok,
     JSON.encode!(%{
       "id" => event.id,
       "label" => @label,
       "type" => "user-transcription",
       "data" => %{
         "text" => event.text,
         "user_id" => event.participant_id,
         "timestamp" => DateTime.to_iso8601(event.occurred_at),
         "final" => event.final
       }
     })}
  end

  @spec encode_event(AgentTurnCompleted.t()) :: {:ok, binary()}
  def encode_event(%AgentTurnCompleted{} = event) do
    {:ok, encode_empty_event(event.id, "bot-stopped-speaking")}
  end

  @spec encode_event(AgentTurnFailed.t()) :: {:ok, binary()}
  def encode_event(%AgentTurnFailed{} = event) do
    {:ok,
     error_response(
       event.correlation_id,
       "The agent could not generate a response. Please try again."
     )}
  end

  @spec encode_event(AgentTurnInterrupted.t()) :: {:ok, binary()}
  def encode_event(%AgentTurnInterrupted{} = event) do
    {:ok, encode_empty_event(event.id, "bot-interrupted")}
  end

  @spec encode_event(AgentSpeechStarted.t()) :: {:ok, binary()}
  def encode_event(%AgentSpeechStarted{} = event) do
    {:ok, encode_empty_event(event.id, "bot-started-speaking")}
  end

  @spec encode_event(ParticipantTurnStarted.t()) :: {:ok, binary()}
  def encode_event(%ParticipantTurnStarted{} = event) do
    {:ok, encode_empty_event(event.id, "user-started-speaking")}
  end

  @spec encode_event(ParticipantTurnCompleted.t()) :: {:ok, binary()}
  def encode_event(%ParticipantTurnCompleted{} = event) do
    {:ok, encode_empty_event(event.id, "user-stopped-speaking")}
  end

  @spec encode_event(ToolCallStarted.t()) :: {:ok, binary()}
  def encode_event(%ToolCallStarted{} = event) do
    {:ok,
     JSON.encode!(%{
       "id" => event.id,
       "label" => @label,
       "type" => "llm-function-call-in-progress",
       "data" => %{
         "tool_call_id" => event.tool_call_id,
         "function_name" => event.name,
         "arguments" => event.arguments
       }
     })}
  end

  @spec encode_event(ToolCallCompleted.t()) :: {:ok, binary()}
  def encode_event(%ToolCallCompleted{} = event) do
    {:ok, encode_tool_call_stopped(event, false, event.result)}
  end

  @spec encode_event(ToolCallFailed.t()) :: {:ok, binary()}
  def encode_event(%ToolCallFailed{} = event) do
    {:ok, encode_tool_call_stopped(event, false, %{"error" => Atom.to_string(event.reason)})}
  end

  @spec encode_event(ToolCallCancelled.t()) :: {:ok, binary()}
  def encode_event(%ToolCallCancelled{} = event) do
    {:ok, encode_tool_call_stopped(event, true, nil)}
  end

  @spec encode_interruption_context(AgentTurnInterrupted.t()) :: {:ok, binary()}
  def encode_interruption_context(%AgentTurnInterrupted{} = event) do
    {:ok,
     JSON.encode!(%{
       "id" => event.id <> "-context",
       "label" => @label,
       "type" => "server-message",
       "data" => %{
         "t" => "vxpipe.turn",
         "v" => 1,
         "d" => %{
           "kind" => "interrupted",
           "turn" => %{
             "agent_participant_id" => event.participant_id,
             "source_participant_id" => event.source_participant_id,
             "connection_id" => event.connection_id,
             "command_id" => event.command_id,
             "correlation_id" => event.correlation_id,
             "played_ms" => event.played_ms
           },
           "interrupted_by" => %{
             "participant_id" => event.interrupted_by_participant_id,
             "connection_id" => event.interrupted_by_connection_id,
             "command_id" => event.interruption_command_id,
             "correlation_id" => event.interruption_correlation_id
           }
         }
       }
     })}
  end

  @spec encode_spoken_progress(
          TextOutput.t(),
          String.t(),
          :in_progress | :completed
        ) ::
          {:ok, binary()}
  def encode_spoken_progress(%TextOutput{} = output, event_id, status)
      when is_binary(event_id) do
    {accumulated_text, remaining_text} =
      case status do
        :in_progress ->
          {"", output.text}

        :completed ->
          {output.text, ""}
      end

    {:ok,
     JSON.encode!(%{
       "id" => event_id <> "-progress",
       "label" => @label,
       "type" => "bot-output",
       "data" => %{
         "text" => output.text,
         "aggregated_by" => aggregation(output.aggregated_by),
         "segment_id" => output.sequence,
         "will_be_spoken" => true,
         "spoken_status" => progress_status(status),
         "spoken_progress" => %{
           "accumulated_text" => accumulated_text,
           "remaining_text" => remaining_text
         }
       }
     })}
  end

  @spec encode_error_response(String.t(), String.t()) :: binary()
  def encode_error_response(id, message) when is_binary(id) and is_binary(message) do
    error_response(id, message)
  end

  defp handle_message(%{
         "id" => id,
         "label" => @label,
         "type" => "client-ready",
         "data" => %{"version" => version}
       })
       when is_binary(id) and is_binary(version) do
    case parse_version(version) do
      {:ok, {@protocol_major, _minor, _patch}} -> {:reply, bot_ready(id)}
      _unsupported_or_invalid -> {:reply, incompatible_version(id, version)}
    end
  end

  defp handle_message(%{
         "id" => id,
         "label" => @label,
         "type" => "send-text",
         "data" => %{"content" => content} = data
       })
       when is_binary(id) and is_binary(content) do
    case send_text_options(Map.get(data, "options", %{})) do
      {:ok, options} ->
        {:command,
         {:send_text,
          %{
            id: id,
            content: content,
            run_immediately: options.run_immediately,
            audio_response: options.audio_response
          }}}

      :error ->
        {:reply, error_response(id, "The send-text options are invalid.")}
    end
  end

  defp handle_message(%{"id" => id, "label" => @label, "type" => "send-text"})
       when is_binary(id) do
    {:reply, error_response(id, "The send-text content is invalid.")}
  end

  defp handle_message(_message), do: :ignore

  defp bot_ready(id) do
    JSON.encode!(%{
      "id" => id,
      "label" => @label,
      "type" => "bot-ready",
      "data" => %{
        "version" => @protocol_version,
        "about" => %{
          "library" => "vxpipe",
          "library_version" => gateway_version()
        }
      }
    })
  end

  defp incompatible_version(id, version) do
    error_response(
      id,
      "RTVI version #{version} is not compatible with server protocol #{@protocol_version}."
    )
  end

  defp error_response(id, message) do
    JSON.encode!(%{
      "id" => id,
      "label" => @label,
      "type" => "error-response",
      "data" => %{"error" => message}
    })
  end

  defp send_text_options(options) when is_map(options) do
    with {:ok, run_immediately} <- optional_boolean(options, "run_immediately", true),
         {:ok, audio_response} <- optional_boolean(options, "audio_response", true) do
      {:ok, %{run_immediately: run_immediately, audio_response: audio_response}}
    else
      :error -> :error
    end
  end

  defp send_text_options(_options), do: :error

  defp optional_boolean(options, key, default) do
    case Map.get(options, key, default) do
      value when is_boolean(value) -> {:ok, value}
      _invalid -> :error
    end
  end

  defp encode_empty_event(id, type) do
    JSON.encode!(%{
      "id" => id,
      "label" => @label,
      "type" => type,
      "data" => nil
    })
  end

  defp encode_tool_call_stopped(event, cancelled, result) do
    data = %{
      "tool_call_id" => event.tool_call_id,
      "function_name" => event.name,
      "cancelled" => cancelled
    }

    data = if result == nil, do: data, else: Map.put(data, "result", result)

    JSON.encode!(%{
      "id" => event.id,
      "label" => @label,
      "type" => "llm-function-call-stopped",
      "data" => data
    })
  end

  defp aggregation(:sentence), do: "sentence"

  defp progress_status(:in_progress), do: "in-progress"
  defp progress_status(:completed), do: "completed"

  defp parse_version(version) do
    with [major, minor, patch] <- String.split(version, "."),
         {major, ""} <- Integer.parse(major),
         {minor, ""} <- Integer.parse(minor),
         {patch, ""} <- Integer.parse(patch),
         true <- major >= 0 and minor >= 0 and patch >= 0 do
      {:ok, {major, minor, patch}}
    else
      _invalid -> :error
    end
  end

  defp gateway_version do
    :vxpipe_gateway
    |> Application.spec(:vsn)
    |> to_string()
  end
end
