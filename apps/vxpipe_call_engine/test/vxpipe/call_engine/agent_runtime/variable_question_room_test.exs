defmodule Vxpipe.CallEngine.VariableQuestionRoomTest do
  use ExUnit.Case, async: false

  import Vxpipe.CallEngine.TestVoiceToolRoom
  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}

  alias Vxpipe.CallEngine.Event.{
    AgentTurnCompleted,
    AgentTurnInterrupted,
    ParticipantTranscription,
    ParticipantTurnStarted,
    TextOutput,
    ToolCallCompleted
  }

  alias Vxpipe.CallEngine.{
    TestAudioOutputSink,
    TestTextToSpeechTransport
  }

  @question "Where do you need the landscaping?"
  @repeat "What is the service area?"

  setup do
    configure()
  end

  for first <- [:model, :playback] do
    test "the next inference after a mixed save sees its outcome during playback, with #{first} finishing first" do
      {_plan, room, caller, voice, sink} = start_intake()
      submit(room, caller, "Florida", "location")
      assert_receive {:test_agent_runtime_stream, model, _}

      message =
        JSON.encode!(%{
          "type" => "participant_message",
          "participant_id" => "agent",
          "agent_mode" => "speaker",
          "message" => "Let me save that."
        })

      write(model, "area", "Florida", "service_area", message)

      assert_receive {:vxpipe_event,
                      %ToolCallCompleted{tool_call_id: "area", result: %{"revision" => 1}}}

      assert_receive {:test_agent_runtime_stream, next, request}
      assert List.last(request.messages).content =~ "Florida"

      assert %{"status" => status, "message" => "Let me save that."} =
               request.model_context["in_flight_audio"]

      assert status in ["queued", "playing"]
      assert_receive {:test_tts_control, ^voice, speak}
      assert JSON.decode!(speak)["text"] == "Let me save that."

      if unquote(first) == :playback do
        settle(voice, sink, "before-save", "location")
        assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "location"}}
        reply(next, :speaker, "Saved Florida.")
      else
        finish_behind_playback(room, next, "Saved Florida.")
        refute_received {:vxpipe_event, %TextOutput{text: "Saved Florida."}}
        premature = JSON.encode!(%{"type" => "Speak", "text" => "Saved Florida."})
        refute_received {:test_tts_control, ^voice, ^premature}
        settle(voice, sink, "before-save", "location")
      end

      assert_receive {:test_tts_control, ^voice, saved}
      assert JSON.decode!(saved)["text"] == "Saved Florida."
      settle(voice, sink, "after-save", request.correlation.tool_context.correlation_id)
    end
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

      write(model, "first", value, "service_type", speaker_preamble(@question))
      assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "first", result: result}}
      assert_receive {:test_tts_control, ^voice, speak}
      assert JSON.decode!(speak)["text"] == @question
      settle(voice, sink, "location", command.correlation_id)
      assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "service"}}
      assert_receive {:test_agent_runtime_stream, continuation, observation}

      completion_request =
        if unquote(outcome) == :invalid do
          assert result["error"]["code"] == "invalid_call_variables_update"
          assert List.last(observation.messages).origin == :engine
          assert List.last(observation.messages).content =~ "expected_schema"
          write(continuation, "corrected", "commercial landscaping")

          assert_receive {:vxpipe_event,
                          %ToolCallCompleted{
                            tool_call_id: "corrected",
                            result: %{"revision" => 1}
                          }}

          assert_receive {:test_agent_runtime_stream, corrected, correction_result}
          assert List.last(correction_result.messages).origin == :engine
          assert List.last(correction_result.messages).content =~ "corrected"
          reply(corrected, :speaker, @repeat)
          correction_result
        else
          assert result["revision"] == 1
          assert List.last(observation.messages).origin == :engine
          assert List.last(observation.messages).content =~ ~s("revision":1)
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

    write(
      first,
      "service-type",
      "commercial landscaping",
      "service_type",
      speaker_preamble(@question)
    )

    assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "service-type"}}
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

    # The variable completion starts while the question still plays. Barge-in
    # cancels it and its released lease restarts it without replaying speech.
    assert_receive {:test_agent_runtime_stream, overlapped, _}
    monitor = Process.monitor(overlapped)
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

    assert_receive {:DOWN, ^monitor, :process, ^overlapped, _}
    # The interrupted completion is consumed, never restarted. The caller
    # keeps priority and a single inference answers the turn.
    refute_received {:test_tts_control, ^voice, _}
    refute_receive {:test_agent_runtime_stream, _, _}, 200
    turn(stt, "EndOfTurn", 2, "Florida")
    assert_receive {:vxpipe_event, %ParticipantTranscription{text: "Florida", final: true}}
    assert_receive {:test_agent_runtime_stream, answer, request}
    assert JSON.decode!(List.last(request.messages).content)["message"] == "Florida"

    assert Enum.any?(
             request.messages,
             &(&1.origin == :engine and &1.content =~ "tool_invocation_completion")
           )

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

    assert_receive {:test_agent_runtime_stream, saved, request}

    assert request.model_context["call_variables"]["sections"]["caller_requests"]["value"] ==
             %{"service_type" => "commercial landscaping", "service_area" => "Florida"}

    reply(saved, :speaker, "Thanks, Florida.")
    assert_receive {:test_tts_control, ^voice, speak}
    assert JSON.decode!(speak)["text"] == "Thanks, Florida."
    settle(voice, sink, "thank-you", request.correlation.tool_context.correlation_id)
  end

  for phase <- [:running, :held] do
    test "a caller correction during save playback keeps one Florida write and saves Georgia with the response #{phase}" do
      {_plan, room, caller, voice, sink} = start_intake()
      assert_receive {:test_stt_transport_started, stt, _}
      submit(room, caller, "Florida", "location")
      assert_receive {:test_agent_runtime_stream, model, _}

      write(
        model,
        "area-florida",
        "Florida",
        "service_area",
        speaker_preamble("Let me save that.")
      )

      assert_receive {:vxpipe_event,
                      %ToolCallCompleted{tool_call_id: "area-florida", result: %{"revision" => 1}}}

      assert_receive {:test_tts_control, ^voice, speak}
      assert JSON.decode!(speak)["text"] == "Let me save that."
      assert_receive {:test_tts_control, ^voice, _flush}

      TestTextToSpeechTransport.deliver_control(
        voice,
        ~s({"type":"SpeechStarted","speech_id":"save-florida"})
      )

      TestTextToSpeechTransport.deliver_audio(voice, :binary.copy(<<1, 0>>, 960))
      assert_receive {:test_audio_output, ^sink, _frame}
      assert :ok = TestAudioOutputSink.playback_started(sink)
      assert :ok = TestAudioOutputSink.playback_progress(sink, 10, 100)

      assert_receive {:test_agent_runtime_stream, overlapped, _}
      monitor = Process.monitor(overlapped)
      if unquote(phase) == :held, do: finish_behind_playback(room, overlapped, "Saved Florida.")
      turn(stt, "StartOfTurn", 1, "Actu")

      assert_receive {:vxpipe_event,
                      %AgentTurnInterrupted{correlation_id: "location", played_ms: 10}}

      assert_receive {:vxpipe_event, %ParticipantTurnStarted{modality: :audio}}
      assert_receive {:test_tts_control, ^voice, interrupt}
      assert JSON.decode!(interrupt)["type"] == "Interrupt"

      TestTextToSpeechTransport.deliver_control(
        voice,
        ~s({"type":"SpeechInterrupted","audio_played_ms":10,"text_spoken":"Let me","text_remaining":"save that.","metadata":{"speech_id":"save-florida"}})
      )

      assert_receive {:DOWN, ^monitor, :process, ^overlapped, _}
      # The interrupted Florida completion is consumed, never restarted. The
      # caller keeps priority and a single inference answers the correction.
      refute_received {:test_tts_control, ^voice, _}
      refute_receive {:test_agent_runtime_stream, _, _}, 200
      turn(stt, "EndOfTurn", 2, "Actually, Georgia")

      assert_receive {:vxpipe_event,
                      %ParticipantTranscription{text: "Actually, Georgia", final: true}}

      assert_receive {:test_agent_runtime_stream, answer, request}
      assert JSON.decode!(List.last(request.messages).content)["message"] == "Actually, Georgia"

      assert Enum.any?(
               request.messages,
               &(&1.origin == :engine and &1.content =~ "tool_invocation_completion")
             )

      refute Enum.any?(request.messages, &(&1.content =~ "Saved Florida."))
      write(answer, "area-georgia", "Georgia", "service_area")

      assert_receive {:vxpipe_event,
                      %ToolCallCompleted{tool_call_id: "area-georgia", result: %{"revision" => 2}}}

      refute_received {:vxpipe_event, %ToolCallCompleted{tool_call_id: "area-florida"}}
      assert_receive {:test_agent_runtime_stream, saved, saved_request}
      assert List.last(saved_request.messages).origin == :engine
      assert List.last(saved_request.messages).content =~ ~s("revision":2)
      reply(saved, :speaker, "Thanks, Georgia.")
      assert_receive {:test_tts_control, ^voice, speak}
      assert JSON.decode!(speak)["text"] == "Thanks, Georgia."
      settle(voice, sink, "thanks-georgia", saved_request.correlation.tool_context.correlation_id)
      refute_received {:test_tts_control, ^voice, _}
    end
  end

  test "a question discarded before playback can still be asked on the variable result" do
    {_plan, room, caller, voice, sink} = start_intake()
    submit(room, caller, "Commercial landscaping", "service")
    assert_receive {:test_agent_runtime_stream, first, _}

    write(
      first,
      "service-type",
      "commercial landscaping",
      "service_type",
      speaker_preamble(@question)
    )

    assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "service-type"}}
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

    assert Enum.any?(
             request.messages,
             &(&1.origin == :engine and &1.content =~ "tool_invocation_completion")
           )

    refute Enum.any?(request.messages, fn message ->
             message.role == :assistant and message.tool_calls == [] and
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

    write(
      first,
      "service-type",
      "commercial landscaping",
      "service_type",
      speaker_preamble("Dites-moi votre ville.")
    )

    assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "service-type"}}
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

  defp finish_behind_playback(room, provider, text) do
    [{room_pid, _}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {room.tenant_id, room.room_id})

    coordinator = :sys.get_state(room_pid).text_capability.pid
    worker = :sys.get_state(coordinator).current.task.pid
    monitor = Process.monitor(worker)
    reply(provider, :speaker, text)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}
    _ = :sys.get_state(coordinator)
    _ = :sys.get_state(room_pid)
    :ok
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

  defp write(model, id, value, field \\ "service_type", text \\ "") do
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

    {:ok, response} = ModelResponse.new(text: text, tool_calls: [call])
    send(model, {:test_agent_runtime_response, {:ok, response}})
  end
end
