defmodule Vxpipe.CallEngine.VariableQuestionRoomTest do
  use ExUnit.Case, async: false

  import Vxpipe.CallEngine.TestVoiceToolRoom
  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}

  alias Vxpipe.CallEngine.Event.{
    AgentTurnCompleted,
    AgentTurnInterrupted,
    ParticipantTranscription,
    ParticipantTurnStarted,
    ToolCallCompleted
  }

  alias Vxpipe.CallEngine.{
    TestSpeechToTextTransport,
    TestTextToSpeechTransport,
    TestAudioOutputSink
  }

  @question "Where do you need the landscaping?"
  @repeat "What is the service area?"

  setup do
    configure()
  end

  for outcome <- [:valid, :invalid] do
    test "a #{outcome} variable write can be processed privately after a question is heard" do
      {_plan, room, caller, voice, sink} = start_intake()
      command = submit(room, caller, "Commercial landscaping", "service")
      assert_receive {:test_agent_runtime_stream, model, _}

      value =
        if unquote(outcome) == :valid,
          do: "commercial landscaping",
          else: %{"service_type" => "commercial landscaping"}

      write(model, "first", value)
      assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "first", result: result}}
      assert_receive {:test_agent_runtime_stream, acknowledgment, _}
      reply(acknowledgment, :speaker, @question)
      assert_receive {:test_tts_control, ^voice, speak}
      assert JSON.decode!(speak)["text"] == @question
      settle(voice, sink, "location", command.correlation_id)
      assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "service"}}
      assert_receive {:test_agent_runtime_stream, continuation, observation}

      completion_request =
        if unquote(outcome) == :invalid do
          assert result["error"]["code"] == "invalid_call_variables_update"
          assert List.last(observation.messages).content =~ "expected_schema"
          write(continuation, "corrected", "commercial landscaping")

          assert_receive {:vxpipe_event,
                          %ToolCallCompleted{
                            tool_call_id: "corrected",
                            result: %{"revision" => 1}
                          }}

          assert_receive {:test_agent_runtime_stream, correction_ack, _}
          reply(correction_ack, :speaker, @repeat)
          assert_receive {:test_agent_runtime_stream, corrected, correction_result}
          reply(corrected, :speaker, @repeat)
          correction_result
        else
          assert result["revision"] == 1
          reply(continuation, :speaker, @repeat)
          observation
        end

      final_correlation = completion_request.correlation.tool_context.correlation_id
      assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: ^final_correlation}}
      refute_received {:test_tts_control, ^voice, _}
      submit(room, caller, "Florida", "answer")
      assert_receive {:test_agent_runtime_stream, next, request}
      assert JSON.decode!(List.last(request.messages).content)["message"] == "Florida"

      refute Enum.any?(request.messages, fn message ->
               is_binary(message.content) and message.content =~ @repeat
             end)

      reply(next, :speaker, "Thanks, Florida.")
      assert_receive {:test_tts_control, ^voice, speak}
      assert JSON.decode!(speak)["text"] == "Thanks, Florida."
      settle(voice, sink, "answer-received", "answer")
    end
  end

  test "caller speech during question playback keeps variable follow-up off the speaker until the answer" do
    {_plan, room, caller, voice, sink} = start_intake()
    assert_receive {:test_stt_transport_started, stt, _}
    submit(room, caller, "Commercial landscaping", "service")
    assert_receive {:test_agent_runtime_stream, first, _}
    write(first, "service-type", "commercial landscaping")
    assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "service-type"}}
    assert_receive {:test_agent_runtime_stream, ack, _}
    reply(ack, :speaker, @question)
    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == @question
    assert_receive {:test_tts_control, ^voice, _flush}

    TestTextToSpeechTransport.deliver_control(
      voice,
      ~s({"type":"SpeechStarted","speech_id":"cut"})
    )

    TestTextToSpeechTransport.deliver_audio(voice, :binary.copy(<<1, 0>>, 960))
    assert_receive {:test_audio_output, ^sink, _}
    assert :ok = TestAudioOutputSink.playback_started(sink)
    assert :ok = TestAudioOutputSink.playback_progress(sink, 10, 100)
    turn(stt, "StartOfTurn", 1, "Flori")

    assert_receive {:vxpipe_event,
                    %AgentTurnInterrupted{correlation_id: "service", played_ms: 10}}

    assert_receive {:vxpipe_event, %ParticipantTurnStarted{modality: :audio}}
    assert_receive {:test_tts_control, ^voice, interrupt}
    assert JSON.decode!(interrupt)["type"] == "Interrupt"

    TestTextToSpeechTransport.deliver_control(
      voice,
      ~s({"type":"SpeechInterrupted","audio_played_ms":10,"text_spoken":"Where","text_remaining":"do you need the landscaping?","metadata":{"speech_id":"cut"}})
    )

    assert_receive {:test_agent_runtime_stream, continuation, _}
    reply(continuation, :speaker, @repeat)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{}}
    refute_received {:test_tts_control, ^voice, _}
    turn(stt, "EndOfTurn", 2, "Florida")
    assert_receive {:vxpipe_event, %ParticipantTranscription{text: "Florida", final: true}}
    assert_receive {:test_agent_runtime_stream, answer, request}
    assert JSON.decode!(List.last(request.messages).content)["message"] == "Florida"
    write(answer, "answered-area", "Florida", "service_area")

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "answered-area",
                      result: %{
                        "section" => "caller_requests",
                        "revision" => 2,
                        "value" => %{
                          "service_type" => "commercial landscaping",
                          "service_area" => "Florida"
                        }
                      }
                    }}

    assert_receive {:test_agent_runtime_stream, acknowledgment, _}
    reply(acknowledgment, :listener, nil)
    assert_receive {:test_agent_runtime_stream, saved, request}

    assert request.model_context["call_variables"]["sections"]["caller_requests"]["value"] ==
             %{"service_type" => "commercial landscaping", "service_area" => "Florida"}

    reply(saved, :speaker, "Thanks, Florida.")
    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == "Thanks, Florida."
    settle(voice, sink, "thank-you", request.correlation.tool_context.correlation_id)
  end

  test "a question discarded before playback can still be asked on the variable result" do
    {_plan, room, caller, voice, sink} = start_intake()
    submit(room, caller, "Commercial landscaping", "service")
    assert_receive {:test_agent_runtime_stream, first, _}
    write(first, "service-type", "commercial landscaping")
    assert_receive {:test_agent_runtime_stream, ack, _}
    reply(ack, :speaker, @question)
    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == @question
    assert_receive {:test_tts_control, ^voice, _flush}
    :ok = GenServer.call(sink, {:block_output, true})

    TestTextToSpeechTransport.deliver_control(
      voice,
      ~s({"type":"SpeechStarted","speech_id":"unheard"})
    )

    TestTextToSpeechTransport.deliver_audio(voice, <<1, 0, 2, 0>>)
    assert_receive {:test_audio_output, ^sink, _frame}
    :ok = GenServer.call(sink, {:complete_output, {:error, :stale_output_generation}})
    assert_receive {:test_audio_output_interrupt, ^sink, "service", 0}

    TestTextToSpeechTransport.deliver_control(
      voice,
      ~s({"type":"SpeechMetadata","speech_id":"unheard"})
    )

    assert_receive {:test_agent_runtime_stream, retry, request}

    refute Enum.any?(request.messages, fn message ->
             is_binary(message.content) and message.content =~ @question
           end)

    reply(retry, :speaker, @question)
    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == @question
    settle(voice, sink, "first-delivery", request.correlation.tool_context.correlation_id)

    submit(room, caller, "Could you repeat the question?", "repeat")
    assert_receive {:test_agent_runtime_stream, repetition, request}

    assert JSON.decode!(List.last(request.messages).content)["message"] ==
             "Could you repeat the question?"

    reply(repetition, :speaker, @question)
    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == @question
    settle(voice, sink, "requested-repetition", "repeat")
  end

  test "a private result can deliver fresh information but cannot replay a delivered imperative" do
    {_plan, room, caller, voice, sink} = start_intake()
    submit(room, caller, "Commercial landscaping", "service")
    assert_receive {:test_agent_runtime_stream, first, _}
    write(first, "service-type", "commercial landscaping")
    assert_receive {:test_agent_runtime_stream, ack, _}
    reply(ack, :speaker, "Dites-moi votre ville.")
    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == "Dites-moi votre ville."
    settle(voice, sink, "heard", "service")
    assert_receive {:test_agent_runtime_stream, private, request}
    reply(private, :speaker, "Dites-moi votre ville. Votre demande est enregistrée.")
    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == "Votre demande est enregistrée."
    settle(voice, sink, "saved", request.correlation.tool_context.correlation_id)
    refute_received {:test_tts_control, ^voice, _}
  end

  defp start_intake do
    start_call(
      speech_to_text: true,
      variable_permissions: %{"caller_requests" => ["read", "write"]},
      call_variables: %{
        "caller_requests" => %{
          schema: %{
            "type" => "object",
            "properties" => %{
              "service_type" => %{"type" => "string"},
              "service_area" => %{"type" => "string"}
            },
            "additionalProperties" => false
          }
        }
      }
    )
  end

  defp write(model, id, value, field \\ "service_type") do
    {:ok, call} =
      ToolCall.new(
        id: id,
        name: "update_variable",
        arguments: %{
          "section_name" => "caller_requests",
          "variable_name" => field,
          "variable_value" => value
        }
      )

    {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(model, {:test_agent_runtime_response, {:ok, response}})
  end

  defp turn(stt, event, sequence, transcript) do
    message = %{
      "type" => "TurnInfo",
      "request_id" => "request-1",
      "sequence_id" => sequence,
      "event" => event,
      "turn_index" => 0,
      "audio_window_start" => 0.0,
      "audio_window_end" => 1.0,
      "transcript" => transcript,
      "words" => [],
      "end_of_turn_confidence" => 0.8
    }

    message = if event == "EndOfTurn", do: Map.put(message, "trigger", "model"), else: message
    TestSpeechToTextTransport.deliver(stt, JSON.encode!(message))
  end
end
