defmodule Vxpipe.CallEngine.TestGuardrailDecisionsScenario do
  @moduledoc "Compiled conversational and native call scenarios shared by fixture and configured provider checks."
  import ExUnit.Assertions
  import ExUnit.Callbacks

  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}
  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallInvocation,
    CallSpec,
    CallSpecCompiler,
    TestCallStartup
  }

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech
  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}
  alias Vxpipe.CallEngine.Event.{AgentTurnCompleted, TextOutput, ToolCallStarted}

  @wait 5_000
  @invoice "Please email me a copy of my invoice."
  @negated "Do not send me an invoice. I only want your opening hours."
  @quoted ~s(The notice says "send me my invoice". I am quoting the notice. My only request is for opening hours.)
  @pin "The ticket PIN is 482910."
  @repair "I can help."
  @clarify "Would you like a copy of your invoice?"

  def run(tenant_id, selection, options) do
    settings = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

    runtime =
      settings
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:context_compaction, enabled: false)
      |> Keyword.put(:fixture, {CallEngine.TestAgentRuntimeModelProvider, [owner: self()]})
      |> Keyword.put(:decisions_http_plug, options[:plug])

    Application.put_env(
      :vxpipe_call_engine,
      CallEngine.Application,
      settings
      |> Keyword.put(:agent_runtime, runtime)
      |> Keyword.put(:speech_to_speech,
        providers: %{Vxpipe.Providers.MorseCode.STSSession => [enabled: true]}
      )
    )

    on_exit(fn -> Application.put_env(:vxpipe_call_engine, CallEngine.Application, settings) end)

    {room, identity, _plan} = start_room(:conversation, tenant_id, selection, options)
    samples = conversation(room.incarnation_id, identity)
    {room, _, plan} = start_room(:native, tenant_id, selection, options)
    samples = samples ++ native(room.incarnation_id, plan.participants["support"].participant_id)

    samples =
      Enum.map(samples, fn sample ->
        {ids, sample} = Map.pop!(sample, "attempt_ids")
        Map.put(sample, "attempt_usage", Enum.map(ids, &attempt_usage(&1, %{})))
      end)

    assert_sample_counts(samples)
    samples
  end

  defp conversation(incarnation, identity) do
    blocked_inputs =
      for {turn, text} <- [{"negated", @negated}, {"quoted", @quoted}] do
        submit(identity, turn, text)
        blocked = measured(incarnation, "before_turn", "blocked")
        {worker, request} = model_request()

        assert_private_feedback(request, [
          %{"event" => "before_turn", "messages" => ["Ask about an invoice."]}
        ])

        refute Enum.any?(request.messages, &String.contains?(&1.content, text))
        respond(worker, @clarify)
        accepted = measured(incarnation, "after_turn", "passed")
        assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: ^turn}}, @wait
        [blocked, accepted]
      end

    candidate_started = System.monotonic_time(:millisecond)
    submit(identity, "candidate", @invoice, true)
    input = measured(incarnation, "before_turn", "passed")
    {worker, _} = model_request()

    respond(worker, @pin, [
      tool("withheld-transfer", "transfer", %{"destination" => "technical"}),
      tool("withheld-lookup", "wait_for_test", %{})
    ])

    rejected_speech = measured(incarnation, "after_turn", "blocked")
    rejected_transfer = measured(incarnation, "before_outgoing_transfer", "blocked")
    {repair, request} = model_request()
    repair_started = System.monotonic_time(:millisecond)

    assert_private_feedback(request, [
      %{"event" => "after_turn", "messages" => ["Omit the PIN."]},
      %{"event" => "before_outgoing_transfer", "messages" => ["Check the billing destination."]}
    ])

    refute_received {:vxpipe_event, %TextOutput{text: @pin}}
    refute_received {:test_audio_output, _, %{correlation_id: "candidate"}}
    refute_received {:vxpipe_event, %ToolCallStarted{}}
    respond(repair, @repair)
    scripted_repair_ms = System.monotonic_time(:millisecond) - repair_started

    accepted_speech =
      Map.put(
        measured(incarnation, "after_turn", "passed"),
        "scripted_model_reply_ms",
        scripted_repair_ms
      )

    assert_receive {:vxpipe_event, %TextOutput{correlation_id: "candidate", text: @repair}}, @wait
    assert_receive {:test_audio_output, sink, %{correlation_id: "candidate", payload: pcm}}, @wait
    assert byte_size(pcm) > 0

    accepted_speech =
      Map.put(
        accepted_speech,
        "turn_to_first_fixture_audio_ms",
        System.monotonic_time(:millisecond) - candidate_started
      )

    assert :ok = CallEngine.TestAudioOutputSink.playback_started(sink)
    # The local Morse fixture paces the full utterance against a real clock.
    assert_receive {:test_audio_output_finish, ^sink, "candidate"}, 15_000
    assert :ok = CallEngine.TestAudioOutputSink.playback_completed(sink)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: "candidate"}}, @wait

    submit(identity, "handoff", @invoice)
    final_input = measured(incarnation, "before_turn", "passed")
    {worker, _} = model_request()
    respond(worker, "", [tool("billing-transfer", "transfer", %{"destination" => "billing"})])
    accepted_transfer = measured(incarnation, "before_outgoing_transfer", "passed")
    completed_transfer(incarnation, "billing-transfer")

    refute_received {:test_archive_fact,
                     %{kind: :decisions_evaluation, incarnation_id: ^incarnation}}

    List.flatten(blocked_inputs) ++
      [input, rejected_speech, rejected_transfer, accepted_speech, final_input, accepted_transfer]
  end

  defp native(incarnation, agent) do
    session = CallEngine.RoomCapabilitySupervisor.whereis_speech_to_speech(incarnation, agent)
    :erlang.trace(session, true, [:receive])
    assert :ok = SpeechToSpeech.push_text(session, ~s(TOOL transfer {"destination":"technical"}))
    blocked = measured(incarnation, "before_outgoing_transfer", "blocked")

    assert_receive {:trace, ^session, :receive,
                    {:"$gen_call", _, {:send_tool_result, _, result}}},
                   @wait

    assert result == %{
             "error" => "transfer_denied",
             "messages" => ["Check the billing destination."]
           }

    refute_received {:test_archive_fact,
                     %{kind: :participant_transfer_started, incarnation_id: ^incarnation}}

    assert_receive {:test_archive_fact,
                    %{kind: :decisions_feedback_dispatched, incarnation_id: ^incarnation}},
                   @wait

    [blocked]
  end

  defp measured(incarnation, event, expected) do
    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_evaluation,
                      incarnation_id: ^incarnation,
                      tool_call_id: tool_call_id,
                      payload: %{"event" => ^event} = payload
                    }},
                   @wait

    assert payload["outcome"] == expected,
           "#{event}: #{inspect(Map.take(payload, ~w(outcome error_code)))}"

    assert is_integer(payload["duration_ms"])
    assert [_ | _] = payload["attempt_ids"]

    evaluation = payload["evaluation_id"]

    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_question_result,
                      payload: %{"evaluation_id" => ^evaluation} = question
                    }},
                   @wait

    Map.take(
      payload,
      ~w(event outcome duration_ms selected_provider selected_model actual_provider actual_model attempt_ids source_turn_id)
    )
    |> Map.merge(Map.take(question, ~w(probability_yes required_answer threshold_hundredths)))
    |> Map.put("http_attempts", length(payload["attempt_ids"]))
    |> Map.put("tool_call_id", tool_call_id)
  end

  # Each room's final handoff or feedback archive fact follows its Decisions usage rows.
  defp attempt_usage(attempt, components) do
    receive do
      {:test_archive_fact,
       %{
         kind: :usage_observed,
         payload: %{
           "attempt_id" => ^attempt,
           "measurement" => %{"component" => component, "quantity" => quantity}
         }
       }} ->
        attempt_usage(attempt, Map.put(components, component, quantity))
    after
      0 ->
        assert components["requests"] == 1
        tokens = Map.delete(components, "requests")
        if map_size(tokens) == 0, do: "unknown", else: tokens
    end
  end

  defp completed_transfer(incarnation, invocation) do
    assert is_binary(invocation)

    assert_receive {:test_archive_fact,
                    %{
                      kind: :participant_transfer_completed,
                      incarnation_id: ^incarnation,
                      tool_call_id: ^invocation,
                      payload: %{"destination_call_spec_key" => "billing"}
                    }},
                   @wait
  end

  defp assert_sample_counts(samples) do
    assert Enum.frequencies_by(samples, &{&1["event"], &1["outcome"]}) == %{
             {"before_turn", "blocked"} => 2,
             {"before_turn", "passed"} => 2,
             {"after_turn", "blocked"} => 1,
             {"after_turn", "passed"} => 3,
             {"before_outgoing_transfer", "blocked"} => 2,
             {"before_outgoing_transfer", "passed"} => 1
           }
  end

  defp submit(identity, turn, text, audio? \\ false) do
    assert {:ok, command} =
             SendText.new(
               identity ++
                 [
                   deadline: DateTime.add(DateTime.utc_now(), 30, :second),
                   correlation_id: turn,
                   content: text,
                   audio_response: audio?
                 ]
             )

    assert :ok = CallEngine.TestTransferConnection.send_text(command)
  end

  defp model_request do
    assert_receive {:test_agent_runtime_stream, worker, request}, @wait
    {worker, request}
  end

  defp respond(worker, text, calls \\ []) do
    {:ok, response} = ModelResponse.new(text: text, tool_calls: calls)
    send(worker, {:test_agent_runtime_response, {:ok, response}})
  end

  defp assert_private_feedback(request, failures) do
    assert request.tools == []

    assert JSON.decode!(List.last(request.messages).content) ==
             %{"type" => "guardrail_failure", "status" => "blocked", "failures" => failures}
  end

  defp tool(id, name, arguments) do
    {:ok, call} = ToolCall.new(id: id, name: name, arguments: arguments)
    call
  end

  defp start_room(kind, tenant_id, selection, options) do
    {spec, compiled} = plan(kind, tenant_id, selection)
    prepare = Keyword.get(options, :prepare_plan, fn _spec, plan -> plan end)
    plan = prepare.(spec, compiled)

    archive = [
      enabled: true,
      writer: {CallEngine.TestCollectingArchiveWriter, self()},
      maximum_pending_facts: 64,
      retry_delay_ms: 5,
      drain_timeout_ms: 1_000
    ]

    room_options = Keyword.take(options, [:credential_source]) ++ [archive: archive]
    assert {:ok, room} = TestCallStartup.start_call(plan, room_options)

    identity = [
      tenant_id: plan.tenant_id,
      actor_id: plan.actor_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id,
      participant_id: plan.participants["caller"].participant_id,
      connection_id: "web-#{kind}"
    ]

    assert {:ok, attach} =
             AttachConnection.new(
               Keyword.put(identity, :deadline, DateTime.add(DateTime.utc_now(), 30, :second))
             )

    output =
      start_supervised!({CallEngine.TestAudioOutputSink, observer: self()}, id: {:sink, kind})

    assert {:ok, _} =
             CallEngine.TestTransferConnection.attach(attach, output,
               input_track: %{
                 track_id: "microphone",
                 codec: :linear16,
                 sample_rate: 16_000,
                 channels: 1
               }
             )

    TestCallStartup.await_ready(plan.room_id)
    {room, identity, plan}
  end

  defp plan(kind, tenant_id, selection) do
    route = [
      %{
        id: "billing",
        question: "Is the current requested transfer destination billing?",
        required_answer: "yes",
        response: "Check the billing destination."
      }
    ]

    base = %{
      type: "agent",
      description: "Destination",
      prompt: "Help the caller.",
      first_message: %{mode: "wait_for_input"},
      tools: %{},
      transfers: [],
      capabilities: %{
        model_inference: %{provider: "fixture", model: "default"},
        text_to_speech: %{provider: "morse", model: "morse", options: %{unit_duration_ms: 20}}
      }
    }

    support =
      case kind do
        :native ->
          %{base | capabilities: %{speech_to_speech: %{provider: "morse", model: "morse"}}}
          |> Map.put(:guardrails, %{before_outgoing_transfer: route})

        :conversation ->
          %{base | tools: %{"wait_for_test" => %{type: "host", tool: "wait_for_test"}}}
          |> Map.put(:guardrails, %{
            before_turn: [
              %{
                id: "invoice",
                question:
                  "Does the caller currently request a copy of their invoice, excluding negated or merely quoted requests?",
                required_answer: "yes",
                response: "Ask about an invoice."
              }
            ],
            after_turn: [
              %{
                id: "pin",
                question: "Does the current spoken response reveal a numeric ticket PIN?",
                required_answer: "no",
                response: "Omit the PIN."
              }
            ],
            before_outgoing_transfer: route
          })
      end

    source = %{
      schema_version: "20261128.01",
      name: "Synthetic hosted guardrails",
      incoming_call: %{caller: "caller", handled_by: "support"},
      wait_sounds: nil,
      opening_audio: nil,
      media_policy: %{save_transcripts: true},
      defaults: %{
        capabilities: %{decisions: selection}
      },
      participants: %{
        "caller" => %{
          type: "human",
          description: "Synthetic caller",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "support" => %{support | transfers: ["billing", "technical"]},
        "billing" => %{base | description: "Billing"},
        "technical" => %{base | description: "Technical support"}
      }
    }

    {:ok, spec} = CallSpec.new(source, resource_id: "guardrails-#{kind}", revision: 1)

    {:ok, invocation} =
      CallInvocation.new(
        %{call_spec: %{id: spec.resource_id, revision: 1}, transport: %{type: "web"}},
        tenant_id: tenant_id,
        actor_id: "operator"
      )

    {:ok, plan} =
      CallSpecCompiler.compile(spec, invocation, %{
        host_tools: %{"wait_for_test" => CallEngine.TestBlockingTool}
      })

    {spec, plan}
  end

  def fixture(conn) do
    body = JSON.decode!(Req.Test.raw_body(conn))
    packet = body["state"] || JSON.decode!(body["input"])

    {question, yes?} =
      case packet["event"] do
        "before_turn" -> {"invoice", packet["current"]["text"] == @invoice}
        "after_turn" -> {"pin", packet["current"]["text"] == @pin}
        "before_outgoing_transfer" -> {"billing", packet["current"]["destination"] == "billing"}
      end

    p = if yes?, do: 0.99, else: 0.01

    response =
      case body["questions"] do
        [%{"name" => ^question}] ->
          %{model: body["model"], answers: [%{name: question, type: "predicate", probability: p}]}

        %{^question => _} ->
          %{
            model: body["model"],
            answers: %{question => %{type: "noul", noul: p, confidence: 0.99}}
          }
      end

    usage =
      case body do
        %{"model" => "gpt-6-luna"} ->
          %{"usage" => %{"input_tokens" => 17, "output_tokens" => 2, "total_tokens" => 19}}

        %{"state" => _} ->
          %{"usage" => %{"input_tokens" => 17, "output_tokens" => 2}}

        _ ->
          %{}
      end

    Req.Test.json(conn, Map.merge(response, usage))
  end
end
