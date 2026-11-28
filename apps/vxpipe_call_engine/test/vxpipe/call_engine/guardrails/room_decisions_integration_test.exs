defmodule Vxpipe.CallEngine.Guardrails.RoomDecisionsIntegrationTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}
  alias Vxpipe.CallEngine.{CallInvocation, CallSpec, CallSpecCompiler, TestCallStartup}
  alias Vxpipe.CallEngine.MediaPolicy.Authority
  alias Vxpipe.CallEngine.TranscriptRouter
  alias Vxpipe.CallEngine.TestTenantCredentialSource

  defp guarded_plan(save_transcripts \\ false, variant \\ :single, tenant \\ "tenant-guarded") do
    source = %{
      schema_version: "20261128.01",
      name: "Guarded startup",
      incoming_call: %{caller: "caller", handled_by: "agent"},
      wait_sounds: nil,
      opening_audio: nil,
      media_policy: %{save_transcripts: save_transcripts},
      defaults: %{
        capabilities: %{
          text_to_speech: %{provider: "morse", model: "morse"},
          model_inference: %{provider: "fixture", model: "default"},
          decisions: %{provider: "openai", model: "gpt-6-luna", credential_name: "policy"}
        }
      },
      participants: %{
        "restrictor" => %{
          type: "human",
          description: "Privacy restriction",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          while_present: %{save_transcripts: false}
        },
        "caller" => %{
          type: "human",
          description: "Caller",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "agent" => %{
          type: "agent",
          description: "Support",
          prompt: "Assist.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: [],
          guardrails: %{
            before_turn: [
              %{
                id: "scope",
                question: "Is this supported?",
                required_answer: "yes",
                response: "Please ask about a supported product."
              }
            ]
          }
        }
      }
    }

    source =
      case variant do
        :handoff ->
          agent = source.participants["agent"]
          [rule] = agent.guardrails.before_turn

          billing = %{
            agent
            | description: "Billing",
              prompt: "Handle billing.",
              guardrails: %{before_turn: [%{rule | required_answer: "no"}]}
          }

          source
          |> put_in([:participants, "agent", :transfers], ["billing"])
          |> put_in([:participants, "billing"], billing)

        :speech ->
          put_in(source, [:defaults, :capabilities, :speech_to_text], %{
            provider: "cartesia",
            model: "ink-2"
          })

        mode when mode in [:turn_context, :mixed_audio] ->
          agent = source.participants["agent"]
          [rule] = agent.guardrails.before_turn

          source =
            source
            |> put_in([:participants, "restrictor", :while_present], %{
              transcript_routes: %{"caller" => []}
            })
            |> put_in([:participants, "agent", :guardrails, :after_turn], [%{rule | id: "output"}])
            |> put_in([:participants, "agent", :guardrails, :before_outgoing_transfer], [
              %{rule | id: "route"}
            ])
            |> put_in([:participants, "agent", :transfers], ["billing", "human-support"])
            |> put_in([:participants, "human-support"], %{
              type: "human",
              description: "Support",
              connection: %{service: "web", mode: "receive", admission: "transfer"}
            })
            |> put_in([:participants, "billing"], %{
              agent
              | description: "Billing",
                guardrails: %{}
            })

          if mode == :mixed_audio do
            source
            |> put_in([:defaults, :capabilities, :text_to_speech], %{
              provider: "deepgram",
              model: "flux-haley-en",
              options: %{encoding: "linear16", sample_rate: 48_000}
            })
            |> put_in([:participants, "agent", :tools, "submitted_host_tool"], %{
              type: "host",
              tool: "submitted_host_tool"
            })
            |> put_in([:participants, "agent", :tools, "wait_for_test"], %{
              type: "host",
              tool: "wait_for_test",
              conversation_mode: "non_blocking"
            })
          else
            source
          end

        :native_transfer ->
          agent = source.participants["agent"]
          [rule] = agent.guardrails.before_turn

          source
          |> update_in([:defaults, :capabilities], &Map.take(&1, [:decisions]))
          |> put_in([:participants, "agent", :capabilities], %{
            speech_to_speech: %{provider: "morse", model: "morse"}
          })
          |> put_in([:participants, "agent", :guardrails], %{before_outgoing_transfer: [rule]})
          |> put_in([:participants, "agent", :transfers], ["billing", "support"])
          |> put_in(
            [:participants, "billing"],
            %{agent | guardrails: %{}, description: "Billing"}
            |> Map.put(:capabilities, %{model_inference: %{provider: "fixture", model: "default"}})
          )
          |> then(fn source ->
            put_in(source, [:participants, "support"], %{
              source.participants["billing"]
              | description: "Support"
            })
          end)

        :after_turn ->
          rules = source.participants["agent"].guardrails.before_turn
          put_in(source, [:participants, "agent", :guardrails], %{after_turn: rules})

        :route_restriction ->
          put_in(source, [:participants, "restrictor", :while_present], %{
            transcript_routes: %{"caller" => []}
          })

        mode when mode in [:generated, :fixed] ->
          rules = source.participants["agent"].guardrails.before_turn

          greeting =
            if mode == :fixed,
              do: %{mode: "fixed", text: "Welcome to support."},
              else: %{mode: "generated"}

          source
          |> put_in([:participants, "agent", :guardrails], %{after_turn: rules})
          |> put_in([:participants, "agent", :first_message], greeting)

        :single ->
          source
      end

    {:ok, spec} =
      CallSpec.new(source,
        resource_id: "guarded-#{System.unique_integer([:positive])}",
        revision: 3
      )

    {:ok, invocation} =
      CallInvocation.new(
        %{call_spec: %{id: spec.resource_id, revision: 3}, transport: %{type: "web"}},
        tenant_id: tenant,
        actor_id: "operator"
      )

    host_tools =
      if variant == :mixed_audio,
        do: %{
          "wait_for_test" => CallEngine.TestBlockingTool,
          "submitted_host_tool" => CallEngine.TestSubmittedHostTool
        },
        else: %{}

    {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: host_tools})
    plan
  end

  test "a typed turn in a compiled guarded room records the retry and its reported evidence" do
    plan = guarded_plan()
    caller = Map.fetch!(plan.participants, "caller")
    agent = Map.fetch!(plan.participants, "agent")
    counter = :atomics.new(1, [])

    plug = fn conn ->
      assert conn.request_path == "/v1/decisions"
      body = JSON.decode!(Req.Test.raw_body(conn))
      assert [%{"name" => "scope"}] = body["questions"]
      current = JSON.decode!(body["input"])["current"]
      assert current["text"] == "Synthetic caller message"
      refute Map.has_key?(current, "correlation")

      case :atomics.add_get(counter, 1, 1) do
        1 ->
          conn
          |> Plug.Conn.put_resp_header("retry-after", "0")
          |> Plug.Conn.put_resp_header("x-request-id", "first-request")
          |> Plug.Conn.put_status(429)
          |> Req.Test.json(%{})

        2 ->
          conn
          |> Plug.Conn.put_resp_header("x-request-id", "retried-request")
          |> Req.Test.json(%{
            "model" => "gpt-6-luna-snapshot",
            "answers" => [%{"name" => "scope", "type" => "predicate", "probability" => 0.9}],
            "usage" => %{"input_tokens" => 12, "output_tokens" => 4, "total_tokens" => 16}
          })
      end
    end

    {_room, identity} = start_guarded_call(plan, plug)

    assert {:ok, command} =
             SendText.new(
               identity ++ [correlation_id: "turn-1", content: "Synthetic caller message"]
             )

    assert :ok = CallEngine.TestTransferConnection.send_text(command)

    assert_receive {:test_archive_fact, %{kind: :decisions_evaluation} = evaluation}, 2_000
    assert evaluation.activation_id == agent.activation_id
    assert evaluation.participant_id == agent.participant_id
    assert evaluation.source_participant_id == caller.participant_id
    assert evaluation.command_id == command.id

    assert %{
             "outcome" => "passed",
             "source_turn_id" => "turn-1",
             "selected_provider" => "openai",
             "selected_model" => "gpt-6-luna",
             "actual_provider" => "openai",
             "actual_model" => "gpt-6-luna-snapshot",
             "actual_request_id" => "retried-request",
             "question_ids" => ["scope"],
             "attempt_ids" => [first_id, second_id],
             "duration_ms" => gate_duration
           } = evaluation.payload

    assert is_integer(gate_duration) and gate_duration >= 0

    assert_receive {:test_archive_fact,
                    %{kind: :decisions_attempt, id: ^first_id, payload: first}}

    assert_receive {:test_archive_fact,
                    %{kind: :decisions_attempt, id: ^second_id, payload: second}}

    assert %{
             "ordinal" => 0,
             "outcome" => "failed",
             "error_code" => "rate_limited",
             "provider" => "openai",
             "model" => nil,
             "request_id" => "first-request"
           } = first

    assert %{
             "ordinal" => 1,
             "outcome" => "succeeded",
             "retry_of" => ^first_id,
             "provider" => "openai",
             "model" => "gpt-6-luna-snapshot",
             "request_id" => "retried-request"
           } = second

    for attempt <- [first, second] do
      assert is_integer(attempt["duration_ms"]) and attempt["duration_ms"] >= 0
      assert {:ok, _, 0} = DateTime.from_iso8601(attempt["started_at"])
      assert {:ok, _, 0} = DateTime.from_iso8601(attempt["ended_at"])
    end

    assert_receive {:test_archive_fact, %{kind: :decisions_question_result, payload: question}}

    assert question["question_id"] == "scope"
    assert question["content_unavailable"] == %{"reason" => "denied"}
    assert question["probability_yes"] == nil
    refute Map.has_key?(question, "question")
    refute Map.has_key?(question, "response")
    refute Map.has_key?(question, "feedback")

    assert_receive {:test_archive_fact,
                    %{
                      kind: :usage_observed,
                      payload: %{"measurement" => %{"component" => "requests"}}
                    }}

    assert_receive {:test_archive_fact,
                    %{
                      kind: :usage_observed,
                      payload: %{"measurement" => %{"component" => "requests"}}
                    }}

    assert_receive {:test_archive_fact,
                    %{
                      kind: :usage_observed,
                      payload: %{"measurement" => %{"component" => "input_tokens"}}
                    }}

    assert :atomics.get(counter, 1) == 2
  end

  defp start_guarded_call(plan, plug, speech_options \\ []) do
    settings = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

    runtime =
      settings
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.merge(Keyword.take(speech_options, [:request_timeout_ms]))
      |> Keyword.merge(
        fixture: {CallEngine.TestAgentRuntimeModelProvider, [owner: self()]},
        decisions_http_plug: plug
      )

    Application.put_env(
      :vxpipe_call_engine,
      CallEngine.Application,
      settings
      |> Keyword.put(:agent_runtime, runtime)
      |> Keyword.merge(Keyword.take(speech_options, [:speech_to_text, :speech_to_speech]))
    )

    on_exit(fn -> Application.put_env(:vxpipe_call_engine, CallEngine.Application, settings) end)

    bindings = %{
      {plan.tenant_id, "openai", "policy"} => %{
        "api_key" => Keyword.get(speech_options, :test_policy_key, "synthetic-policy-key")
      },
      {plan.tenant_id, "deepgram", "default"} => %{"api_key" => "synthetic-tts-key"},
      {plan.tenant_id, "cartesia", "default"} => %{"api_key" => "synthetic-stt-key"}
    }

    assert {:ok, room} =
             TestCallStartup.start_call(plan,
               archive: [
                 enabled: true,
                 writer: {CallEngine.TestCollectingArchiveWriter, self()},
                 maximum_pending_facts: 64,
                 retry_delay_ms: 5,
                 drain_timeout_ms: 1_000
               ],
               credential_source: {TestTenantCredentialSource, {self(), bindings}}
             )

    identity = [
      tenant_id: plan.tenant_id,
      actor_id: plan.actor_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id,
      participant_id: plan.participants["caller"].participant_id,
      connection_id: Keyword.get(speech_options, :connection_id, "guarded-web"),
      deadline: DateTime.add(DateTime.utc_now(), 5, :second)
    ]

    assert {:ok, attach} = AttachConnection.new(identity)

    output =
      start_supervised!({CallEngine.TestAudioOutputSink, observer: self()},
        id: {:sink, plan.room_id}
      )

    assert {:ok, _attachment} =
             CallEngine.TestTransferConnection.attach(
               attach,
               output,
               Keyword.take(speech_options, [:input_track])
             )

    if not Keyword.has_key?(speech_options, :speech_to_text),
      do: TestCallStartup.await_ready(plan.room_id)

    {room, identity}
  end

  for {initial, terminal} <- [{false, true}, {true, false}, {true, true}] do
    @initial initial
    @terminal terminal
    test "a pending typed check preserves source storage permission #{@initial} through #{@terminal}" do
      check_source_policy_transition(@initial, @terminal)
    end
  end

  test "a private evaluation preserves the checked outgoing draft when storage stays permitted" do
    check_source_policy_transition(true, true, :after_turn)
  end

  test "a generated reply retains the agent source interval while its provider check waits" do
    check_source_policy_transition(false, true, :after_turn)
  end

  test "a caller hidden from the receiving agent cannot reach the Decisions provider" do
    plan = guarded_plan(true, :route_restriction)
    {room, identity} = start_guarded_call(plan, controlled_decisions(self()))
    authority = Authority.whereis(room.incarnation_id)
    assert {:ok, _} = Authority.admit(authority, plan.participants["restrictor"].participant_id)
    send_turn(identity, "hidden-at-submit", "Current caller content")

    assert_receive {:vxpipe_event,
                    %CallEngine.Event.AgentTurnFailed{correlation_id: "hidden-at-submit"}},
                   2_000

    refute_received {:gate, _, _, _}
    refute_received {:test_agent_runtime_stream, _, _}
  end

  test "a revoked source cannot issue a second HTTP request after a retryable response" do
    plan = guarded_plan(true, :route_restriction)
    {room, identity} = start_guarded_call(plan, controlled_decisions(self()))
    agent = plan.participants["agent"].participant_id
    send_turn(identity, "revoked-retry", "Only the first attempt is permitted")
    submitted = assert_held(agent, "Only the first attempt is permitted")
    authority = Authority.whereis(room.incarnation_id)
    assert {:ok, _} = Authority.admit(authority, plan.participants["restrictor"].participant_id)
    send(submitted, :outage)

    assert_receive {:vxpipe_event,
                    %CallEngine.Event.AgentTurnFailed{correlation_id: "revoked-retry"}},
                   2_000

    assert_receive {:test_archive_fact,
                    %{kind: :decisions_evaluation, payload: %{"attempt_ids" => [attempt]}}}

    assert_receive {:test_archive_fact,
                    %{kind: :decisions_attempt, payload: %{"attempt_id" => ^attempt}}}

    refute_received {:gate, _, _, _}
    refute_received {:test_agent_runtime_stream, _, _}
  end

  for score <- [0.1, 0.9] do
    @score score
    test "revocation fences a held Decisions score of #{@score} at session admission" do
      plan = guarded_plan(true, :route_restriction)
      {room, identity} = start_guarded_call(plan, controlled_decisions(self()))
      agent = plan.participants["agent"]
      send_turn(identity, "revoked-at-session", "Original caller content")
      http = assert_held(agent.participant_id, "Original caller content")
      authority = Authority.whereis(room.incarnation_id)
      assert {:ok, _} = Authority.admit(authority, plan.participants["restrictor"].participant_id)
      send(http, {:score, @score})

      assert_receive {:vxpipe_event,
                      %CallEngine.Event.AgentTurnFailed{correlation_id: "revoked-at-session"}},
                     2_000

      refute_received {:test_agent_runtime_stream, _, _}
      refute_received {:test_agent_runtime_generate, _, _}
      assert_receive {:test_archive_fact, %{kind: :decisions_attempt}}
    end

    test "revocation after a score of #{@score} fences the request already queued at the session" do
      check_revocation_at_session(@score)
    end
  end

  defp check_revocation_at_session(score) do
    plan = guarded_plan(true, :route_restriction)
    {room, identity} = start_guarded_call(plan, controlled_decisions(self()))
    agent = plan.participants["agent"]
    session = CallEngine.AgentActivationSupervisor.whereis_child(agent.activation_id, :session)
    send_turn(identity, "queued-at-session", "Caller content awaiting model admission")
    http = assert_held(agent.participant_id, "Caller content awaiting model admission")
    :ok = :sys.suspend(session)
    1 = :erlang.trace(session, true, [:receive])

    try do
      send(http, {:score, score})
      expected = if score < 0.7, do: "blocked", else: "passed"

      assert_receive {:test_archive_fact,
                      %{kind: :decisions_evaluation, payload: %{"outcome" => ^expected}}},
                     2_000

      assert_receive {:trace, ^session, :receive,
                      {:"$gen_call", _, {:request_guarded, _, _, _, _}}},
                     2_000

      authority = Authority.whereis(room.incarnation_id)
      assert {:ok, _} = Authority.admit(authority, plan.participants["restrictor"].participant_id)
    after
      :erlang.trace(session, false, [:receive])
      :ok = :sys.resume(session)
    end

    assert_receive {:vxpipe_event,
                    %CallEngine.Event.AgentTurnFailed{correlation_id: "queued-at-session"}},
                   2_000

    refute_received {:test_agent_runtime_stream, _, _}
    refute_received {:test_agent_runtime_generate, _, _}
    refute_received {:test_archive_fact, %{kind: :decisions_feedback_dispatched}}
  end

  defp check_source_policy_transition(initial, terminal, event \\ :before_turn) do
    plan = guarded_plan(true, if(event == :after_turn, do: :after_turn, else: :single))
    observer = self()

    plug = fn conn ->
      send(observer, {:submitted, self()})

      receive do
        :return_decision ->
          Req.Test.json(conn, %{
            "model" => "gpt-6-luna",
            "answers" => [%{"name" => "scope", "type" => "predicate", "probability" => 0.9}]
          })
      end
    end

    {room, identity} = start_guarded_call(plan, plug)
    authority = Authority.whereis(room.incarnation_id)
    restrictor = plan.participants["restrictor"].participant_id
    if not initial, do: assert({:ok, _} = Authority.admit(authority, restrictor))
    caller = plan.participants["caller"].participant_id
    agent = plan.participants["agent"].participant_id
    source = if event == :before_turn, do: caller, else: agent
    router = TranscriptRouter.whereis(room.incarnation_id)

    assert {:ok,
            %{
              source_policy: %{
                "save_transcripts" => ^initial,
                "media_policy_revision" => initial_revision
              }
            }} =
             TranscriptRouter.project_current(router, source, MapSet.new([agent]))

    assert {:ok, command} =
             SendText.new(identity ++ [correlation_id: "held", content: "Synthetic input"])

    assert :ok = CallEngine.TestTransferConnection.send_text(command)

    if event == :after_turn do
      assert_receive {:test_agent_runtime_stream, model, _request}, 2_000
      assert {:ok, reply} = Vxpipe.AgentRuntime.ModelResponse.new(text: "A synthetic reply.")
      send(model, {:test_agent_runtime_response, {:ok, reply}})
    end

    assert_receive {:submitted, worker}, 2_000

    case {initial, terminal} do
      {false, true} -> assert {:ok, _} = Authority.leave(authority, restrictor)
      {true, false} -> assert {:ok, _} = Authority.admit(authority, restrictor)
      _ -> :ok
    end

    assert {:ok, %{source_policy: %{"save_transcripts" => ^terminal}}} =
             TranscriptRouter.project_current(router, source, MapSet.new([agent]))

    send(worker, :return_decision)

    assert_receive {:test_archive_fact, %{kind: :decisions_question_result} = question}, 2_000

    assert_receive {:test_archive_fact, %{kind: :decisions_evaluation} = evaluation}, 2_000
    assert evaluation.id == question.payload["evaluation_id"]

    if initial and terminal do
      text = if event == :before_turn, do: "Synthetic input", else: "A synthetic reply."
      assert evaluation.payload["checked_text"] == text
    else
      refute Map.has_key?(evaluation.payload, "checked_text")
    end

    if initial and terminal do
      assert question.payload["question"] == "Is this supported?"
      assert question.payload["probability_yes"] == 0.9
    else
      assert question.payload["content_unavailable"] == %{"reason" => "denied"}
      refute Map.has_key?(question.payload, "question")
      assert question.payload["probability_yes"] == nil
    end

    assert question.source_policy["media_policy_revision"] == initial_revision
    assert_receive {:test_archive_fact, %{kind: :decisions_attempt} = attempt}
    assert attempt.tenant_id == plan.tenant_id
    assert attempt.incarnation_id == room.incarnation_id
    assert attempt.activation_id == plan.participants["agent"].activation_id
    assert attempt.source_policy == question.source_policy
  end

  test "guarded input, speech and transfer send permitted history and a separate current event" do
    plan = guarded_plan(true, :turn_context)
    caller = plan.participants["caller"].participant_id
    agent = plan.participants["agent"].participant_id
    owner = self()

    plug = fn conn ->
      body = JSON.decode!(Req.Test.raw_body(conn))
      packet = JSON.decode!(body["input"])
      send(owner, {:evidence, packet})

      Req.Test.json(conn, %{
        model: "gpt-6-luna",
        answers:
          Enum.map(body["questions"], fn question ->
            %{
              name: question["name"],
              type: "predicate",
              probability: if(packet["current"]["text"] == "Next reply.", do: 0.01, else: 0.99)
            }
          end)
      })
    end

    {room, identity} = start_guarded_call(plan, plug)
    send_turn(identity, "one", "Permitted caller text.")

    assert_receive {:evidence,
                    %{"event" => "before_turn", "recent_context" => %{"messages" => []}}},
                   2000

    assert_receive {:test_agent_runtime_stream, provider, _}, 2000
    {:ok, response} = Vxpipe.AgentRuntime.ModelResponse.new(text: "Permitted reply.")
    send(provider, {:test_agent_runtime_response, {:ok, response}})
    first = %{"participant_id" => caller, "text" => "Permitted caller text."}

    assert_receive {:evidence,
                    %{
                      "event" => "after_turn",
                      "current" => %{"text" => "Permitted reply."},
                      "triggering_input" => ^first
                    }},
                   2000

    assert_receive {:vxpipe_event, %CallEngine.Event.AgentTurnCompleted{}}, 2000
    %{id: command_id} = send_turn(identity, "two", "Next caller text.")
    second = %{"participant_id" => agent, "text" => "Permitted reply."}

    assert_receive {:evidence,
                    %{
                      "event" => "before_turn",
                      "recent_context" => %{"messages" => [^first, ^second], "omitted" => false}
                    }},
                   2000

    assert_receive {:test_agent_runtime_stream, provider, _}, 2000

    {:ok, call} =
      Vxpipe.AgentRuntime.ToolCall.new(
        id: "route-2",
        name: "transfer",
        arguments: %{"destination" => "human-support", "reason" => "Billing question"}
      )

    {:ok, response} =
      Vxpipe.AgentRuntime.ModelResponse.new(text: "Next reply.", tool_calls: [call])

    send(provider, {:test_agent_runtime_response, {:ok, response}})
    trigger = %{"participant_id" => caller, "text" => "Next caller text."}

    assert_receive {:evidence,
                    %{
                      "event" => "after_turn",
                      "recent_context" => %{"messages" => [^first, ^second]},
                      "triggering_input" => ^trigger
                    }},
                   2000

    assert_receive {:evidence,
                    %{
                      "event" => "before_outgoing_transfer",
                      "current" => current,
                      "recent_context" => %{"messages" => [^first, ^second]},
                      "triggering_input" => ^trigger
                    }},
                   2000

    assert current == %{
             "text" => "Next reply.",
             "reason" => "Billing question",
             "destination" => "human-support",
             "proposed_calls" => [%{"name" => "transfer", "kind" => "transfer"}]
           }

    assert_receive {:test_agent_runtime_stream, repair, repair_request}, 2000

    [feedback] =
      for %{role: :user, origin: :engine} = message <- repair_request.messages,
          message.content =~ "guardrail_failure",
          do: JSON.decode!(message.content)

    assert feedback == %{
             "type" => "guardrail_failure",
             "status" => "blocked",
             "failures" =>
               Enum.map(
                 ["after_turn", "before_outgoing_transfer"],
                 &%{"event" => &1, "messages" => ["Please ask about a supported product."]}
               )
           }

    refute_received {:test_archive_fact, %{kind: :decisions_feedback_dispatched}}
    send(repair, {:test_agent_runtime_delta, "I will help you here."})

    for {event, id} <- [{"after_turn", "output"}, {"before_outgoing_transfer", "route"}] do
      assert_receive {:test_archive_fact,
                      %{
                        kind: :decisions_evaluation,
                        command_id: ^command_id,
                        payload:
                          %{
                            "event" => ^event,
                            "outcome" => "blocked",
                            "source_turn_id" => "two",
                            "response_turn_id" => "two",
                            "candidate_attempt_id" => "two:1",
                            "evaluation_id" => evaluation
                          } = payload
                      }},
                     1000

      assert payload["proposed_calls"] == [%{"id" => "route-2", "name" => "transfer"}]
      assert payload["checked_text"] == "Next reply."

      if event == "before_outgoing_transfer" do
        assert payload["transfer_invocation_id"] == "route-2"
        assert payload["requested_destination"] == "human-support"

        assert_receive {:test_archive_fact,
                        %{
                          kind: :usage_observed,
                          payload: %{
                            "attribution" => %{"turn_id" => "two", "tool_call_id" => "route-2"}
                          }
                        }},
                       1_000
      end

      assert_receive {:test_archive_fact,
                      %{
                        kind: :decisions_feedback_dispatched,
                        payload: %{"evaluation_id" => ^evaluation, "question_ids" => [^id]}
                      }},
                     1000
    end

    {:ok, response} = Vxpipe.AgentRuntime.ModelResponse.new(text: "I will help you here.")
    send(repair, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:evidence,
                    %{
                      "event" => "after_turn",
                      "recent_context" => %{"messages" => [^first, ^second]},
                      "triggering_input" => ^trigger,
                      "current" => %{"text" => "I will help you here."}
                    }},
                   2000

    assert_receive {:vxpipe_event, %CallEngine.Event.AgentTurnCompleted{}}, 2000
    authority = CallEngine.MediaPolicy.Authority.whereis(room.incarnation_id)
    restrictor = plan.participants["restrictor"].participant_id
    assert {:ok, _} = CallEngine.MediaPolicy.Authority.admit(authority, restrictor)
    assert {:ok, _} = CallEngine.MediaPolicy.Authority.leave(authority, restrictor)
    send_turn(identity, "three", "Fresh permitted message.")

    assert_receive {:evidence,
                    %{
                      "event" => "before_turn",
                      "recent_context" => %{"messages" => released, "omitted" => true}
                    }},
                   2000

    refute Enum.any?(released, &(&1["participant_id"] == caller))
  end

  test "a reply to blocked input gives the checker the caller trigger while the model receives only private feedback" do
    plan = guarded_plan(false, :turn_context)
    owner = self()

    plug = fn conn ->
      body = JSON.decode!(Req.Test.raw_body(conn))
      packet = JSON.decode!(body["input"])
      send(owner, {:packet, packet})
      probability = if packet["event"] == "before_turn", do: 0.0, else: 1.0

      Req.Test.json(conn, %{
        model: "gpt-6-luna",
        answers:
          Enum.map(body["questions"], fn q ->
            %{name: q["name"], type: "predicate", probability: probability}
          end)
      })
    end

    {_room, identity} = start_guarded_call(plan, plug)
    send_turn(identity, "blocked-trigger", "The blocked source text.")
    assert_receive {:packet, %{"event" => "before_turn"}}, 2000
    assert_receive {:test_agent_runtime_stream, model, request}, 2000
    refute Enum.any?(request.messages, &String.contains?(&1.content, "The blocked source text."))

    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_evaluation,
                      payload: %{
                        "event" => "before_turn",
                        "outcome" => "blocked",
                        "evaluation_id" => evaluation
                      }
                    }}

    refute_received {:test_archive_fact, %{kind: :decisions_feedback_dispatched}}
    send(model, {:test_agent_runtime_delta, "Can you clarify?"})

    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_feedback_dispatched,
                      payload:
                        %{
                          "evaluation_id" => ^evaluation,
                          "content_unavailable" => %{"reason" => "denied"}
                        } = payload
                    }},
                   1000

    refute Map.has_key?(payload, "question_ids")
    {:ok, response} = Vxpipe.AgentRuntime.ModelResponse.new(text: "Can you clarify?")
    send(model, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:packet,
                    %{
                      "event" => "after_turn",
                      "triggering_input" => %{"text" => "The blocked source text."},
                      "recent_context" => %{"messages" => []}
                    }},
                   2000
  end

  test "the native provider receives only the private denial lines and archives one correlated dispatch" do
    alias Vxpipe.CallEngine.{Capability.SpeechToSpeech, RoomCapabilitySupervisor}
    plan = guarded_plan(true, :native_transfer)

    {room, _identity} =
      start_guarded_call(plan, controlled_decisions(self(), "native-inspection"),
        speech_to_speech: [providers: %{Vxpipe.Providers.MorseCode.STSSession => [enabled: true]}],
        input_track: %{track_id: "microphone", codec: :linear16, sample_rate: 16_000, channels: 1}
      )

    agent = plan.participants["agent"].participant_id
    capability = RoomCapabilitySupervisor.whereis_speech_to_speech(room.incarnation_id, agent)
    1 = :erlang.trace(capability, true, [:receive])
    assert :ok = SpeechToSpeech.push_text(capability, ~s(TOOL transfer {"destination":"billing"}))
    assert_receive {:gate, http, ^agent, ""}, 2000

    assert_receive {:vxpipe_event,
                    %CallEngine.Event.ToolCallStarted{name: "transfer", command_id: command_id}},
                   1000

    assert is_binary(command_id)
    assert_receive {:scoped_wire, "native-inspection", _, packet}
    refute Map.has_key?(packet["current"], "correlation")
    refute Map.has_key?(packet["current"], "command_id")
    refute_received {:test_archive_fact, %{kind: :decisions_feedback_dispatched}}
    send(http, {:score, 0.1})

    assert_receive {:trace, ^capability, :receive,
                    {:"$gen_call", _, {:send_tool_result, _, result}}},
                   2000

    assert result == %{
             "error" => "transfer_denied",
             "messages" => ["Please ask about a supported product."]
           }

    assert_receive {:vxpipe_event,
                    %CallEngine.Event.ToolCallFailed{
                      reason: :transfer_denied,
                      tool_call_id: invocation
                    }},
                   2000

    assert_receive {:test_archive_fact,
                    %{
                      kind: :participant_transfer_failed,
                      command_id: ^command_id,
                      tool_call_id: ^invocation,
                      payload: %{"cause" => "transfer_guardrail_blocked"} = denial
                    }},
                   2_000

    refute Map.has_key?(denial, "feedback_digest")
    refute Map.has_key?(denial, "messages")

    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_evaluation,
                      command_id: ^command_id,
                      tool_call_id: ^invocation,
                      payload: %{"evaluation_id" => evaluation}
                    }},
                   2000

    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_feedback_dispatched,
                      command_id: ^command_id,
                      tool_call_id: ^invocation,
                      payload: %{"evaluation_id" => ^evaluation, "question_ids" => ["scope"]}
                    }},
                   2000

    refute_received {:test_archive_fact, %{kind: :participant_transfer_started}}
    refute_received {:test_archive_fact, %{kind: :decisions_feedback_dispatched}}

    assert :ok = SpeechToSpeech.push_text(capability, ~s(TOOL transfer {"destination":"billing"}))
    assert_receive {:gate, next_http, ^agent, ""}, 2_000

    assert_receive {:vxpipe_event,
                    %CallEngine.Event.ToolCallStarted{
                      command_id: next_command_id,
                      tool_call_id: next_invocation
                    }},
                   2_000

    assert is_binary(next_command_id)
    refute next_command_id == command_id
    refute next_invocation == invocation
    refute_received {:test_archive_fact, %{kind: :participant_transfer_started}}
    send(next_http, {:score, 0.99})

    assert_receive {:test_archive_fact,
                    %{
                      kind: :participant_transfer_completed,
                      command_id: ^next_command_id,
                      tool_call_id: ^next_invocation,
                      payload: %{"destination_call_spec_key" => "billing"}
                    }},
                   2_000

    refute_received {:test_archive_fact, %{kind: :participant_transfer_completed}}
  end

  test "a replayed native transfer with a changed allowed destination commits the original handoff once" do
    {plan, room, _identity, capability, http, invocation} = held_native_transfer()
    provider = CallEngine.Speech.Session.provider(:sys.get_state(capability).session)

    :sys.replace_state(provider, fn state ->
      [{call, association}] = Map.to_list(state.pending_tools)

      for destination <- ["billing", "support"] do
        assert :ok =
                 CallEngine.Speech.Event.emit(state.channel, :tool_call,
                   call_ref: call,
                   turn_ref: association.turn_ref,
                   tool_name: "transfer",
                   arguments: %{"destination" => destination}
                 )
      end

      state
    end)

    send(http, {:score, 0.99})

    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_evaluation,
                      tool_call_id: ^invocation,
                      payload: %{"source_turn_id" => nil, "outcome" => "passed"}
                    }},
                   2_000

    assert_receive {:test_archive_fact,
                    %{
                      kind: :participant_transfer_completed,
                      tool_call_id: ^invocation,
                      payload: %{"destination_call_spec_key" => "billing"}
                    }},
                   2_000

    assert_receive {:vxpipe_event,
                    %CallEngine.Event.ToolCallCompleted{tool_call_id: ^invocation}},
                   2_000

    assert {:ok, _} =
             CallEngine.participant_snapshot(
               plan.tenant_id,
               room.room_id,
               plan.participants["billing"].participant_id
             )

    refute_received {:test_archive_fact, %{kind: :participant_transfer_completed}}
    refute_received {:gate, _, _, _}
  end

  test "a native transfer verdict returned after the caller disconnects cannot start preparation" do
    {plan, room, identity, _capability, http, invocation} = held_native_transfer()
    [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, room.room_id})
    {:ok, command} = AttachConnection.new(identity)
    monitor = Process.monitor(http)

    assert :ok =
             CallEngine.TestTransferConnection.run(command, fn ->
               CallEngine.RoomAuthority.detach_connection(authority, command, self())
             end)

    assert_receive {:test_archive_fact, %{kind: :connection_detached}}, 2_000
    send(http, {:score, 0.99})
    assert_receive {:DOWN, ^monitor, :process, ^http, _}, 2_000

    assert_receive {:test_archive_fact,
                    %{kind: :decisions_evaluation, tool_call_id: ^invocation}},
                   2_000

    _ = :sys.get_state(authority)
    refute_received {:test_archive_fact, %{kind: :participant_transfer_started}}
    refute_received {:test_archive_fact, %{kind: :participant_transfer_completed}}
  end

  defp held_native_transfer do
    plan = guarded_plan(true, :native_transfer)

    {room, identity} =
      start_guarded_call(plan, controlled_decisions(self()),
        speech_to_speech: [providers: %{Vxpipe.Providers.MorseCode.STSSession => [enabled: true]}],
        input_track: %{track_id: "microphone", codec: :linear16, sample_rate: 16_000, channels: 1}
      )

    agent = plan.participants["agent"].participant_id

    capability =
      CallEngine.RoomCapabilitySupervisor.whereis_speech_to_speech(room.incarnation_id, agent)

    assert :ok =
             CallEngine.Capability.SpeechToSpeech.push_text(
               capability,
               ~s(TOOL transfer {"destination":"billing"})
             )

    assert_receive {:gate, http, ^agent, ""}, 2_000

    assert_receive {:vxpipe_event,
                    %CallEngine.Event.ToolCallStarted{name: "transfer", tool_call_id: invocation}},
                   2_000

    refute_received {:test_archive_fact, %{kind: :participant_transfer_started}}
    {plan, room, identity, capability, http, invocation}
  end

  defp controlled_decisions(observer, scope \\ nil) do
    fn conn ->
      body = JSON.decode!(Req.Test.raw_body(conn))
      input = JSON.decode!(body["input"])

      if scope do
        identified? =
          Plug.Conn.get_req_header(conn, "authorization") == ["Bearer synthetic-#{scope}"]

        send(observer, {:scoped_wire, scope, identified?, input})
      end

      send(observer, {:gate, self(), input["participant"], input["current"]["text"]})

      receive do
        {:score, value} ->
          Req.Test.json(conn, %{
            "model" => "gpt-6-luna",
            "usage" => %{"total_tokens" => 7},
            "answers" =>
              Enum.map(
                body["questions"],
                &%{"name" => &1["name"], "type" => "predicate", "probability" => value}
              )
          })

        :malformed_with_usage ->
          Req.Test.json(conn, %{
            "model" => "failed-snapshot",
            "answers" => [],
            "usage" => %{"total_tokens" => 13}
          })

        :outage ->
          conn
          |> Plug.Conn.put_resp_header("retry-after", "0")
          |> Plug.Conn.put_status(503)
          |> Req.Test.json(%{})
      after
        3_000 -> flunk("Decisions HTTP response timed out")
      end
    end
  end

  defp send_turn(identity, turn, text) do
    assert {:ok, command} =
             SendText.new(
               identity ++ [correlation_id: turn, content: text, audio_response: false]
             )

    assert :ok = CallEngine.TestTransferConnection.send_text(command)
    command
  end

  for {scenario, args} <- [
        duplicate_transfers: [
          {"transfer", %{"destination" => "human-support", "reason" => "First reason"}},
          {"transfer", %{"destination" => "human-support", "reason" => "Second reason"}}
        ],
        unknown_target: [{"transfer", %{"destination" => "restrictor"}}],
        missing_human_reason: [{"transfer", %{"destination" => "human-support"}}],
        blank_human_reason: [{"transfer", %{"destination" => "human-support", "reason" => "  "}}],
        unexpected_agent_reason: [
          {"transfer", %{"destination" => "billing", "reason" => "For a human"}}
        ],
        malformed_ordinary: [
          {"submitted_host_tool", %{"value" => 42}},
          {"transfer", %{"destination" => "billing"}}
        ]
      ] do
    @invalid_args args
    @tag :guarded_invalid_batch
    @tag :physical_guarded_round
    test "a guarded mixed round fails as invalid_response before any sibling starts for #{scenario}" do
      assert_invalid_batch(@invalid_args)
    end
  end

  defp assert_invalid_batch(arguments) do
    :ok = CallEngine.TestVoiceToolRoom.configure()
    Application.put_env(:vxpipe_call_engine, :blocking_tool_observer, self())
    on_exit(fn -> Application.delete_env(:vxpipe_call_engine, :blocking_tool_observer) end)
    plan = guarded_plan(true, :mixed_audio)
    {_room, identity} = start_guarded_call(plan, controlled_audio_decisions(self()))
    assert_receive {:test_tts_transport_started, voice, _}, 2_000

    {:ok, command} =
      SendText.new(
        identity ++
          [correlation_id: "invalid-mixed", content: "Connect me.", audio_response: true]
      )

    assert :ok = CallEngine.TestTransferConnection.send_text(command)
    assert_receive {:test_agent_runtime_stream, model, _}, 2_000
    alias Vxpipe.AgentRuntime.ToolCall
    {:ok, ordinary} = ToolCall.new(id: "ordinary", name: "wait_for_test", arguments: %{})

    calls =
      for {name, args} <- arguments, reduce: [ordinary] do
        acc ->
          {:ok, proposed} = ToolCall.new(id: "action-#{length(acc)}", name: name, arguments: args)
          acc ++ [proposed]
      end

    send_audio_candidate(model, "One moment.", calls)

    assert_receive {:vxpipe_event,
                    %CallEngine.Event.AgentTurnFailed{
                      correlation_id: "invalid-mixed",
                      reason: :invalid_response
                    }},
                   2_000

    refute_received {:audio_gate, _, _}
    refute_received {:test_archive_fact, %{kind: :participant_transfer_started}}
    refute_received {:test_agent_runtime_stream, _, _}
    assert_audio_withheld(voice)
  end

  for outcome <- [
        :mixed_approved,
        :approved_repair,
        :exhausted_repairs,
        :exhausted_http,
        :ordinary_failure,
        :caller_interrupt
      ] do
    @outcome outcome
    @tag :physical_guarded_round
    test "the physical TTS sink releases only admitted mixed-round speech: #{@outcome}" do
      check_mixed_audio(@outcome)
    end
  end

  defp check_mixed_audio(outcome) do
    alias Vxpipe.AgentRuntime.ToolCall
    :ok = CallEngine.TestVoiceToolRoom.configure()
    Application.put_env(:vxpipe_call_engine, :blocking_tool_observer, self())
    on_exit(fn -> Application.delete_env(:vxpipe_call_engine, :blocking_tool_observer) end)
    plan = guarded_plan(true, :mixed_audio)
    {_room, identity} = start_guarded_call(plan, controlled_audio_decisions(self()))
    assert_receive {:test_tts_transport_started, voice, _}, 2_000

    assert {:ok, command} =
             SendText.new(
               identity ++
                 [
                   correlation_id: "mixed-audio",
                   content: "Connect me.",
                   audio_response: true
                 ]
             )

    assert :ok = CallEngine.TestTransferConnection.send_text(command)
    assert_receive {:test_agent_runtime_stream, model, request}, 2_000

    assert Enum.all?(["wait_for_test", "transfer"], fn name ->
             Enum.any?(request.tools, &(&1.name == name))
           end)

    {:ok, lookup} = ToolCall.new(id: "proposed-lookup", name: "wait_for_test", arguments: %{})

    {:ok, transfer} =
      ToolCall.new(
        id: "proposed-transfer",
        name: "transfer",
        arguments: %{"destination" => "billing"}
      )

    send_audio_candidate(model, "A withheld preamble. Please wait.", [transfer, lookup])
    assert_receive {:audio_gate, "after_turn", after_turn}, 2_000
    assert_receive {:audio_gate, "before_outgoing_transfer", transfer_gate}, 2_000
    assert_audio_withheld(voice)

    send(after_turn, {:score, 0.99})
    command_id = command.id

    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_evaluation,
                      participant_id: agent,
                      activation_id: activation,
                      command_id: ^command_id,
                      payload: %{
                        "event" => "after_turn",
                        "outcome" => "passed",
                        "candidate_attempt_id" => candidate,
                        "checked_text" => "A withheld preamble. Please wait."
                      }
                    }},
                   2_000

    assert_audio_withheld(voice)

    if outcome in [:ordinary_failure, :caller_interrupt] do
      send(transfer_gate, {:score, 0.99})
      assert_receive {:test_blocking_tool_started, ordinary}, 2_000
      key = {command_id, "proposed-transfer"}

      assert {:ok, _} =
               CallEngine.RoomAuthority.take_transfer_verdict(plan.tenant_id, plan.room_id, key)

      case outcome do
        :ordinary_failure ->
          send(ordinary, :fail_test_tool)

          assert_receive {:vxpipe_event,
                          %CallEngine.Event.ToolCallFailed{tool_call_id: "proposed-lookup"}},
                         2_000

        :caller_interrupt ->
          {:ok, next} =
            SendText.new(
              identity ++
                [correlation_id: "replace-mixed", content: "Stop.", audio_response: false]
            )

          assert :ok = CallEngine.TestTransferConnection.send_text(next)

          assert_receive {:vxpipe_event,
                          %CallEngine.Event.AgentTurnInterrupted{command_id: ^command_id}},
                         2_000

          next_id = next.id

          assert_receive {:test_agent_runtime_stream, _,
                          %{correlation: %{command_id: ^next_id}, messages: messages}},
                         2_000

          results =
            for %{role: :tool, tool_call_id: id, content: content} <- messages,
                into: %{},
                do: {id, JSON.decode!(content)}

          assert results["proposed-lookup"]["status"] == "running"
          assert results["proposed-transfer"] == %{"status" => "rejected", "reason" => "stale"}
          send(ordinary, :release_test_tool)
      end

      assert :empty =
               CallEngine.RoomAuthority.take_transfer_verdict(plan.tenant_id, plan.room_id, key)

      refute_received {:test_archive_fact, %{kind: :participant_transfer_started}}
    else
      finish_mixed_audio(outcome, transfer_gate, voice)

      case outcome do
        :mixed_approved ->
          assert_receive {:test_archive_fact,
                          %{
                            kind: :participant_transfer_completed,
                            participant_id: ^agent,
                            activation_id: ^activation,
                            command_id: ^command_id,
                            tool_call_id: "proposed-transfer"
                          }},
                         2_000

        :approved_repair ->
          assert_receive {:test_archive_fact,
                          %{
                            kind: :decisions_evaluation,
                            participant_id: ^agent,
                            activation_id: ^activation,
                            command_id: ^command_id,
                            tool_call_id: "proposed-transfer",
                            payload: %{
                              "event" => "before_outgoing_transfer",
                              "outcome" => "blocked",
                              "candidate_attempt_id" => ^candidate,
                              "checked_text" => "A withheld preamble. Please wait."
                            }
                          }},
                         2_000

        _ ->
          :ok
      end
    end
  end

  defp finish_mixed_audio(:mixed_approved, transfer, voice) do
    send(transfer, {:score, 0.99})
    assert_receive {:test_blocking_tool_started, lookup}, 2_000
    assert_receive {:test_tts_control, ^voice, speak}, 2_000
    assert JSON.decode!(speak) == %{"type" => "Speak", "text" => "A withheld preamble."}
    assert_delivered_audio(voice, "mixed-preamble")
    send(lookup, :release_test_tool)

    assert_receive {:vxpipe_event,
                    %CallEngine.Event.ToolCallCompleted{tool_call_id: "proposed-transfer"}},
                   2_000
  end

  defp finish_mixed_audio(:exhausted_http, transfer, voice) do
    send(transfer, :outage)
    assert_receive {:audio_gate, "before_outgoing_transfer", retry}, 2_000
    assert_audio_withheld(voice)
    send(retry, :outage)
    assert_failed_without_audio(voice)
  end

  defp finish_mixed_audio(outcome, transfer, voice) do
    send(transfer, {:score, 0.01})
    assert_receive {:test_agent_runtime_stream, repair, %{tools: []}}, 2_000
    assert_audio_withheld(voice)

    replacement_text =
      if outcome == :approved_repair,
        do: "The approved replacement.",
        else: "A rejected replacement."

    send_audio_candidate(repair, replacement_text, [])
    assert_receive {:audio_gate, "after_turn", replacement}, 2_000
    assert_audio_withheld(voice)

    if outcome == :approved_repair do
      send(replacement, {:score, 0.99})
      assert_receive {:test_tts_control, ^voice, speak}, 2_000
      assert JSON.decode!(speak) == %{"type" => "Speak", "text" => "The approved replacement."}
      assert_delivered_audio(voice, "approved-replacement")

      assert_receive {:vxpipe_event,
                      %CallEngine.Event.AgentTurnCompleted{correlation_id: "mixed-audio"}},
                     2_000

      refute_received {:test_tts_control, ^voice, _}
      refute_received {:test_audio_output, _, _}
      refute_received {:vxpipe_event, %CallEngine.Event.ToolCallStarted{}}
    else
      send(replacement, {:score, 0.01})
      assert_receive {:test_agent_runtime_stream, last_repair, %{tools: []}}, 2_000
      assert_audio_withheld(voice)
      send_audio_candidate(last_repair, "Another withheld replacement.", [])
      assert_receive {:audio_gate, "after_turn", last_check}, 2_000
      assert_audio_withheld(voice)
      send(last_check, {:score, 0.01})
      assert_failed_without_audio(voice)
    end
  end

  defp assert_delivered_audio(voice, speech_id) do
    assert_receive {:test_tts_control, ^voice, flush}, 2_000
    assert JSON.decode!(flush)["type"] == "Flush"
    wire = CallEngine.TestTextToSpeechTransport
    wire.deliver_control(voice, JSON.encode!(%{type: "SpeechStarted", speech_id: speech_id}))
    pcm = <<1, 0, 2, 0>>
    wire.deliver_audio(voice, pcm)

    assert_receive {:test_audio_output, sink, %{correlation_id: "mixed-audio", payload: ^pcm}},
                   2_000

    wire.deliver_control(voice, JSON.encode!(%{type: "SpeechMetadata", speech_id: speech_id}))
    assert_receive {:test_audio_output_finish, ^sink, "mixed-audio"}, 2_000
    :ok = CallEngine.TestAudioOutputSink.playback_started(sink)
    :ok = CallEngine.TestAudioOutputSink.playback_completed(sink)
  end

  defp assert_failed_without_audio(voice) do
    assert_receive {:vxpipe_event,
                    %CallEngine.Event.AgentTurnFailed{correlation_id: "mixed-audio"}},
                   2_000

    assert_audio_withheld(voice)
    refute_received {:test_agent_runtime_stream, _, _}
  end

  defp assert_audio_withheld(voice) do
    refute_received {:test_tts_control, ^voice, _}
    refute_received {:test_audio_output, _, _}
    refute_received {:vxpipe_event, %CallEngine.Event.TextOutput{}}
    refute_received {:vxpipe_event, %CallEngine.Event.ToolCallStarted{}}
    refute_received {:test_blocking_tool_started, _}
  end

  defp send_audio_candidate(model, text, calls) do
    send(model, {:test_agent_runtime_delta, text, self()})
    assert_receive {:test_agent_runtime_delta_result, :ok}, 2_000
    {:ok, response} = Vxpipe.AgentRuntime.ModelResponse.new(text: text, tool_calls: calls)
    send(model, {:test_agent_runtime_response, {:ok, response}})
  end

  defp controlled_audio_decisions(observer) do
    fn conn ->
      body = JSON.decode!(Req.Test.raw_body(conn))
      %{"event" => event} = JSON.decode!(body["input"])

      result =
        if event == "before_turn" do
          {:score, 0.99}
        else
          send(observer, {:audio_gate, event, self()})

          receive do
            {:score, _} = score -> score
            :outage -> :outage
          after
            2_000 -> flunk("No answer was supplied for the held Decisions request")
          end
        end

      case result do
        :outage ->
          conn
          |> Plug.Conn.put_resp_header("retry-after", "0")
          |> Plug.Conn.put_status(503)
          |> Req.Test.json(%{})

        {:score, score} ->
          Req.Test.json(conn, %{
            answers:
              Enum.map(
                body["questions"],
                &%{
                  name: &1["name"],
                  type: "predicate",
                  probability: score
                }
              )
          })
      end
    end
  end

  defp assert_held(id, text) do
    assert_receive {:gate, http, ^id, ^text}, 2_000
    refute_received {:test_agent_runtime_stream, _, _}
    refute_received {:test_agent_runtime_generate, _, _}
    refute_received {:vxpipe_event, %CallEngine.Event.ToolCallStarted{}}
    http
  end

  defp set_deadlines(evaluation_ms, response_ms) do
    previous = Application.get_env(:vxpipe_call_engine, :guardrail_deadlines)

    Application.put_env(:vxpipe_call_engine, :guardrail_deadlines,
      evaluation_ms: evaluation_ms,
      response_ms: response_ms
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:vxpipe_call_engine, :guardrail_deadlines, previous),
        else: Application.delete_env(:vxpipe_call_engine, :guardrail_deadlines)
    end)
  end

  test "a configured evaluation deadline ends a held typed input before the model" do
    set_deadlines(80, 3_000)
    plan = guarded_plan(true)
    {_room, identity} = start_guarded_call(plan, controlled_decisions(self()))
    send_turn(identity, "short-check", "Wait for the checker.")
    _http = assert_held(plan.participants["agent"].participant_id, "Wait for the checker.")

    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_evaluation,
                      payload: %{
                        "source_turn_id" => "short-check",
                        "outcome" => "cancelled",
                        "error_code" => "timeout"
                      }
                    }},
                   700

    assert_receive {:vxpipe_event,
                    %CallEngine.Event.AgentTurnFailed{correlation_id: "short-check"}},
                   700

    refute_received {:test_agent_runtime_stream, _, _}
  end

  test "a shorter existing model request timeout also bounds the initial check" do
    set_deadlines(3_000, 3_000)
    plan = guarded_plan(true)

    {_room, identity} =
      start_guarded_call(plan, controlled_decisions(self()), request_timeout_ms: 120)

    send_turn(identity, "model-limit", "Held before model admission.")
    _http = assert_held(plan.participants["agent"].participant_id, "Held before model admission.")

    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_evaluation,
                      payload: %{"source_turn_id" => "model-limit", "error_code" => "timeout"}
                    }},
                   700

    refute_received {:test_agent_runtime_stream, _, _}
  end

  test "a fixed greeting check expires with the shorter whole-response budget" do
    set_deadlines(3_000, 150)
    plan = guarded_plan(true, :fixed)
    start_guarded_call(plan, controlled_decisions(self()))
    assert_receive {:gate, _, _, _}, 1_000

    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_evaluation,
                      payload: %{"event" => "after_turn", "error_code" => "timeout"}
                    }},
                   700

    refute_received {:vxpipe_event, %CallEngine.Event.TextOutput{}}
    refute_received {:test_agent_runtime_stream, _, _}
  end

  test "a guarded generated greeting and its tool-free rewrite share one absolute deadline" do
    set_deadlines(3_000, 600)
    plan = guarded_plan(true, :generated)
    start_guarded_call(plan, controlled_decisions(self()))
    assert_receive {:test_agent_runtime_stream, first, initial}, 2_000
    deadline = Map.get(initial.correlation, :deadline_ms)
    assert is_integer(deadline)
    {:ok, response} = Vxpipe.AgentRuntime.ModelResponse.new(text: "Synthetic draft.")
    send(first, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:gate, check, _, _}, 1_000
    send(check, {:score, 0.1})
    assert_receive {:test_agent_runtime_stream, _, rewrite}, 1_000
    assert Map.get(rewrite.correlation, :deadline_ms) == deadline
    assert rewrite.tools == []

    assert_receive {:vxpipe_event, %CallEngine.Event.AgentTurnFailed{reason: :provider_timeout}},
                   1_000

    refute_received {:vxpipe_event, %CallEngine.Event.TextOutput{}}
  end

  test "an earlier command deadline ends guarded model generation after the input check passes" do
    set_deadlines(5_000, 5_000)
    plan = guarded_plan(true)
    {_room, identity} = start_guarded_call(plan, controlled_decisions(self()))
    command_deadline = DateTime.add(DateTime.utc_now(), 350, :millisecond)

    send_turn(
      Keyword.put(identity, :deadline, command_deadline),
      "early-command",
      "Short command."
    )

    http = assert_held(plan.participants["agent"].participant_id, "Short command.")
    send(http, {:score, 0.9})
    assert_receive {:test_agent_runtime_stream, _, ordinary}, 700
    assert is_integer(Map.get(ordinary.correlation, :deadline_ms))

    assert_receive {:vxpipe_event,
                    %CallEngine.Event.AgentTurnFailed{
                      correlation_id: "early-command",
                      reason: :provider_timeout
                    }},
                   1_000
  end

  test "one compiled call independently gates two receiving activations across a handoff" do
    alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}
    plan = guarded_plan(true, :handoff)
    {_room, identity} = start_guarded_call(plan, controlled_decisions(self()))
    source = plan.participants["agent"]
    dest = plan.participants["billing"]
    source_id = source.participant_id
    dest_id = dest.participant_id

    activation =
      CallEngine.AgentActivationSupervisor.whereis_child(source.activation_id, :guardrails)

    monitor = Process.monitor(activation)
    text = "Please connect me with billing."

    send_turn(identity, "stale-turn", "Earlier source input")
    stale = assert_held(source_id, "Earlier source input")
    send_turn(identity, "source-turn", text)
    http = assert_held(source_id, text)
    send(http, {:score, 0.9})

    assert_receive {:test_agent_runtime_stream, model, ordinary}, 2_000
    assert Enum.any?(ordinary.messages, &String.contains?(&1.content, text))
    assert Enum.any?(ordinary.tools, &(&1.name == "transfer"))

    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_evaluation,
                      participant_id: ^source_id,
                      payload: %{"source_turn_id" => "source-turn", "outcome" => "passed"}
                    }},
                   2_000

    {:ok, call} =
      ToolCall.new(
        id: "route-to-billing",
        name: "transfer",
        arguments: %{"destination" => "billing"}
      )

    {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(model, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_event,
                    %CallEngine.Event.ToolCallCompleted{tool_call_id: "route-to-billing"}},
                   2_000

    assert_receive {:DOWN, ^monitor, :process, ^activation, _}, 2_000

    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_evaluation,
                      payload: %{
                        "source_turn_id" => "stale-turn",
                        "outcome" => "cancelled",
                        "attempt_ids" => [old_attempt]
                      }
                    }},
                   2_000

    send(stale, :malformed_with_usage)

    assert_receive {:test_archive_fact,
                    %{
                      kind: :usage_observed,
                      participant_id: ^source_id,
                      payload: %{
                        "attempt_id" => ^old_attempt,
                        "outcome" => "failed",
                        "measurement" => %{
                          "component" => "total_tokens",
                          "quantity" => 13,
                          "status" => "correction"
                        }
                      }
                    }},
                   2_000

    send_turn(identity, "destination-turn", text)
    assert_receive {:gate, dest_http, ^dest_id, ^text}, 2_000

    refute_received {:test_agent_runtime_stream, _,
                     %{correlation: %{tool_context: %{correlation_id: "destination-turn"}}}}

    send(dest_http, {:score, 0.9})

    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_evaluation,
                      participant_id: ^dest_id,
                      payload: %{"source_turn_id" => "destination-turn", "outcome" => "blocked"}
                    }},
                   2_000

    assert_receive {:test_agent_runtime_stream, _,
                    %{correlation: %{tool_context: %{correlation_id: "destination-turn"}}} =
                      private},
                   2_000

    assert private.tools == []

    assert List.last(private.messages).content |> JSON.decode!() == %{
             "type" => "guardrail_failure",
             "status" => "blocked",
             "failures" => [
               %{
                 "event" => "before_turn",
                 "messages" => ["Please ask about a supported product."]
               }
             ]
           }

    refute_received {:test_archive_fact,
                     %{
                       kind: :decisions_evaluation,
                       payload: %{"source_turn_id" => "stale-turn", "outcome" => "passed"}
                     }}
  end

  test "stopping a prepared activation during a pending check leaves the active receiver usable" do
    alias CallEngine.AgentRuntime.Coordinator
    alias CallEngine.RoomAuthority.ParticipantLifecycle
    plan = guarded_plan(true, :handoff)
    {room, identity} = start_guarded_call(plan, controlled_decisions(self()))
    agent = plan.participants["agent"]
    billing = plan.participants["billing"]
    runtime = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

    credentials = %{
      {plan.tenant_id, "openai", "policy"} => %{"api_key" => "synthetic-policy-key"}
    }

    assert {:ok, destination} =
             CallEngine.PlanStartup.agent_destination(plan, billing,
               owner: self(),
               incarnation_id: room.incarnation_id,
               agent_runtime: Keyword.fetch!(runtime, :agent_runtime),
               credential_source: {TestTenantCredentialSource, {self(), credentials}}
             )

    assert {:ok, prepared} =
             ParticipantLifecycle.prepare(destination.command, room.incarnation_id,
               agent_activation: destination.agent_activation
             )

    receiving =
      CallEngine.AgentActivationSupervisor.whereis_child(billing.activation_id, :coordinator)

    stopped = Process.monitor(receiving)

    assert {:ok, _} =
             Authority.admit(Authority.whereis(room.incarnation_id), billing.participant_id)

    command = send_turn(identity, "shared-turn", "The same source turn.")

    assert {:ok, %{source_policy: policy}} =
             TranscriptRouter.project_current(
               TranscriptRouter.whereis(room.incarnation_id),
               command.participant_id,
               MapSet.new([billing.participant_id])
             )

    assert :ok = Coordinator.respond(receiving, %{command | source_transcript_policy: policy})
    waiting = assert_held(agent.participant_id, command.content)
    late = assert_held(billing.participant_id, command.content)

    # Transfer preparation may be abandoned while its owner has network I/O pending.
    assert :ok =
             CallEngine.RoomParticipantSupervisor.stop_participant(
               room.incarnation_id,
               prepared.participant_supervisor
             )

    assert_receive {:DOWN, ^stopped, :process, ^receiving, _}, 2_000
    send(late, {:score, 0.9})
    send(waiting, {:score, 0.9})
    assert_receive {:test_agent_runtime_stream, _, ordinary}, 2_000
    assert ordinary.correlation.tool_context.agent_participant_id == agent.participant_id
    assert ordinary.correlation.tool_context.correlation_id == "shared-turn"
    refute_received {:test_agent_runtime_stream, _, _}
  end

  test "ending the entire room stops the held transport and its admission process" do
    plan = guarded_plan(true)
    {room, identity} = start_guarded_call(plan, controlled_decisions(self()))
    participant = plan.participants["agent"]

    admission =
      CallEngine.AgentActivationSupervisor.whereis_child(participant.activation_id, :guardrails)

    send_turn(identity, "end-call", "The call is ending.")
    wire = assert_held(participant.participant_id, "The call is ending.")
    wire_monitor = Process.monitor(wire)
    admission_monitor = Process.monitor(admission)
    assert :ok = CallEngine.end_call(plan.tenant_id, plan.room_id, room.incarnation_id)
    assert_receive {:DOWN, ^wire_monitor, :process, ^wire, _}, 2_000
    assert_receive {:DOWN, ^admission_monitor, :process, ^admission, _}, 2_000
    refute_received {:test_agent_runtime_stream, _, _}
  end

  test "simultaneous guarded calls isolate reversed verdicts and the surviving tenant's admissions" do
    a = guarded_plan(true, :single, "tenant-a")
    b = guarded_plan(true, :single, "tenant-b")

    {room_a, left} =
      start_guarded_call(a, controlled_decisions(self(), a.tenant_id),
        connection_id: "web-a",
        test_policy_key: "synthetic-tenant-a"
      )

    {room_b, right} =
      start_guarded_call(b, controlled_decisions(self(), b.tenant_id),
        connection_id: "web-b",
        test_policy_key: "synthetic-tenant-b"
      )

    send_turn(left, "same-turn", "Only tenant A's invoice.")
    wire_a = scoped_wire(a, "Only tenant A's invoice.")
    send_turn(right, "same-turn", "Only tenant B's ticket.")
    wire_b = scoped_wire(b, "Only tenant B's ticket.")
    refute_received {:test_agent_runtime_stream, _, _}
    send(wire_b, {:score, 0.99})
    {provider_b, request_b} = scoped_model(b)

    assert JSON.decode!(List.last(request_b.messages).content)["message"] ==
             "Only tenant B's ticket."

    refute_received {:test_agent_runtime_stream, _, _}

    send(wire_a, {:score, 0.01})
    {provider_a, request_a} = scoped_model(a)
    assert request_a.tools == []
    assert JSON.decode!(List.last(request_a.messages).content)["type"] == "guardrail_failure"
    refute Enum.any?(request_a.messages, &String.contains?(&1.content, "tenant"))
    {evaluation_a, attempt_a} = scoped_archive(a, room_a, "same-turn", "blocked")
    {evaluation_b, attempt_b} = scoped_archive(b, room_b, "same-turn", "passed")
    assert evaluation_a != evaluation_b
    assert attempt_a != attempt_b

    for {model, reply} <- [{provider_a, "A's reply."}, {provider_b, "B's reply."}] do
      send(
        model,
        {:test_agent_runtime_response, Vxpipe.AgentRuntime.ModelResponse.new(text: reply)}
      )
    end

    for room <- [room_a, room_b] do
      incarnation = room.incarnation_id

      assert_receive {:vxpipe_event,
                      %CallEngine.Event.AgentTurnCompleted{incarnation_id: ^incarnation}},
                     2_000
    end

    send_turn(left, "held-at-end", "Closing tenant A.")
    wire_a = scoped_wire(a, "Closing tenant A.")
    send_turn(right, "held-at-end", "Continuing tenant B.")
    wire_b = scoped_wire(b, "Continuing tenant B.")
    ref = Process.monitor(wire_a)
    assert :ok = CallEngine.end_call(a.tenant_id, a.room_id, room_a.incarnation_id)
    assert_receive {:DOWN, ^ref, :process, ^wire_a, _}, 2_000
    refute_received {:test_agent_runtime_stream, _, _}
    send(wire_b, {:score, 0.99})
    {survivor, request} = scoped_model(b)
    assert JSON.decode!(List.last(request.messages).content)["message"] == "Continuing tenant B."
    scoped_archive(b, room_b, "held-at-end", "passed")

    send(
      survivor,
      {:test_agent_runtime_response, Vxpipe.AgentRuntime.ModelResponse.new(text: "Still here.")}
    )

    assert_receive {:vxpipe_event,
                    %CallEngine.Event.AgentTurnCompleted{correlation_id: "held-at-end"}},
                   2_000

    refute_received {:test_agent_runtime_stream, _, _}
  end

  defp scoped_wire(plan, text) do
    tenant = plan.tenant_id
    agent = plan.participants["agent"].participant_id
    caller = plan.participants["caller"].participant_id

    assert_receive {:scoped_wire, ^tenant, true,
                    %{
                      "participant" => ^agent,
                      "source_participant_id" => ^caller,
                      "current" => %{"text" => ^text}
                    } = packet},
                   2_000

    allowed = [agent, caller]
    assert Enum.all?(packet["recent_context"]["messages"], &(&1["participant_id"] in allowed))
    assert_receive {:gate, wire, ^agent, ^text}, 2_000
    wire
  end

  defp scoped_model(plan) do
    tenant = plan.tenant_id
    room = plan.room_id

    assert_receive {:test_agent_runtime_stream, worker,
                    %{correlation: %{tool_context: %{tenant_id: ^tenant, room_id: ^room}}} =
                      request},
                   2_000

    {worker, request}
  end

  defp scoped_archive(plan, room, turn, outcome) do
    tenant = plan.tenant_id
    call = plan.call_id
    room_id = plan.room_id
    incarnation = room.incarnation_id
    agent = plan.participants["agent"]
    activation = agent.activation_id
    participant = agent.participant_id

    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_evaluation,
                      tenant_id: ^tenant,
                      call_id: ^call,
                      room_id: ^room_id,
                      incarnation_id: ^incarnation,
                      participant_id: ^participant,
                      activation_id: ^activation,
                      payload: %{
                        "evaluation_id" => evaluation,
                        "attempt_ids" => [attempt],
                        "source_turn_id" => ^turn,
                        "outcome" => ^outcome
                      }
                    }},
                   2_000

    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_attempt,
                      tenant_id: ^tenant,
                      call_id: ^call,
                      room_id: ^room_id,
                      incarnation_id: ^incarnation,
                      activation_id: ^activation,
                      payload: %{"evaluation_id" => ^evaluation, "attempt_id" => ^attempt}
                    }},
                   2_000

    assert_receive {:test_archive_fact,
                    %{
                      kind: :usage_observed,
                      tenant_id: ^tenant,
                      call_id: ^call,
                      room_id: ^room_id,
                      incarnation_id: ^incarnation,
                      participant_id: ^participant,
                      payload: %{
                        "attempt_id" => ^attempt,
                        "measurement" => %{"component" => "total_tokens", "quantity" => 7}
                      }
                    }},
                   2_000

    {evaluation, attempt}
  end

  test "a provider outage fails the before-turn gate without a conversational reply" do
    plan = guarded_plan(true)
    {_room, identity} = start_guarded_call(plan, controlled_decisions(self()))
    text = "Test a provider outage."
    send_turn(identity, "outage", text)

    for _attempt <- 1..2 do
      http = assert_held(plan.participants["agent"].participant_id, text)
      send(http, :outage)
    end

    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_evaluation,
                      payload: %{"outcome" => "error", "source_turn_id" => "outage"}
                    }},
                   2_000

    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_question_result,
                      payload: %{"outcome" => "unavailable"} = question
                    }},
                   2_000

    refute question["feedback"]

    assert_receive {:vxpipe_event, %CallEngine.Event.AgentTurnFailed{correlation_id: "outage"}},
                   2_000

    refute_received {:test_agent_runtime_stream, _, _}
    refute_received {:test_agent_runtime_generate, _, _}
  end

  test "only a final nonempty STT turn reaches the receiving agent's before-turn check" do
    alias CallEngine.TestCartesiaSTTTransport, as: Wire
    alias CallEngine.Event.ParticipantTranscription
    set_deadlines(1_000, 2_000)
    plan = guarded_plan(true, :speech)

    settings = [
      speech_to_text: [
        providers: %{
          Vxpipe.Providers.Cartesia.STTSession => [
            enabled: true,
            wire_module: Wire,
            wire_options: [observer: self()],
            media_ingress: [
              maximum_frames: 50,
              maximum_bytes: 262_144,
              maximum_age_ms: 2_000,
              maximum_consecutive_overflows: 5
            ]
          ]
        }
      ],
      input_track: %{
        track_id: "guarded-audio",
        codec: :linear16,
        sample_rate: 16_000,
        channels: 1
      }
    ]

    {_room, identity} = start_guarded_call(plan, controlled_decisions(self()), settings)
    assert_receive {:cartesia_stt_started, wire, _}, 2_000
    assert :ok = Wire.deliver(wire, %{type: "connected", request_id: "room"})
    TestCallStartup.await_ready(plan.room_id)

    assert {:ok, attach} = AttachConnection.new(identity)
    attachment = CallEngine.TestTransferConnection.attachment(attach)

    assert :ok =
             CallEngine.push_audio(attachment, %CallEngine.Media.AudioFrame{
               tenant_id: plan.tenant_id,
               room_id: plan.room_id,
               incarnation_id: attach.incarnation_id,
               participant_id: attach.participant_id,
               connection_id: attach.connection_id,
               track_id: "guarded-audio",
               codec: :linear16,
               sample_rate: 16_000,
               channels: 1,
               sequence_number: 0,
               timestamp: 0,
               payload: <<1, 0>>,
               received_at: System.monotonic_time(:millisecond)
             })

    assert_receive {:cartesia_stt_audio, ^wire, <<1, 0>>}, 2_000

    assert_unscoped_stt_is_denied(plan, identity)

    assert {:error, _} = SendText.new(identity ++ [correlation_id: "blank", content: "   "])

    {:ok, wrong_connection} =
      SendText.new(
        Keyword.merge(identity,
          participant_id: plan.participants["restrictor"].participant_id,
          correlation_id: "wrong-source",
          content: "This source did not attach."
        )
      )

    assert {:error, _} = CallEngine.TestTransferConnection.send_text(wrong_connection)
    refute_received {:gate, _, _, _}

    assert :ok = Wire.deliver(wire, %{type: "turn.start", request_id: "room"})
    assert :ok = Wire.deliver(wire, %{type: "turn.end", request_id: "room", transcript: ""})
    assert :ok = Wire.deliver(wire, %{type: "turn.start", request_id: "room"})

    assert :ok =
             Wire.deliver(wire, %{
               type: "turn.update",
               request_id: "room",
               transcript: "Finished"
             })

    assert_receive {:vxpipe_event, %ParticipantTranscription{final: false, text: "Finished"}},
                   2_000

    refute_received {:gate, _, _, _}

    assert :ok =
             Wire.deliver(wire, %{
               type: "turn.end",
               request_id: "room",
               transcript: "Finished evidence."
             })

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{
                      final: true,
                      text: "Finished evidence.",
                      correlation_id: turn
                    }},
                   2_000

    http = assert_held(plan.participants["agent"].participant_id, "Finished evidence.")
    send(http, {:score, 0.9})

    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_evaluation,
                      payload: %{"source_turn_id" => ^turn, "outcome" => "passed"}
                    }},
                   2_000

    assert_receive {:test_agent_runtime_stream, _, ordinary}, 2_000
    remaining = ordinary.correlation.deadline_ms - System.monotonic_time(:millisecond)
    assert remaining > 0 and remaining <= 2_000
    assert Enum.any?(ordinary.messages, &String.contains?(&1.content, "Finished evidence."))
    refute_received {:gate, _, _, _}
  end

  defp assert_unscoped_stt_is_denied(plan, identity) do
    alias CallEngine.Provider.SpeechToText.Signal
    [{room, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})
    connection = :sys.get_state(room).connections[Keyword.fetch!(identity, :connection_id)]
    capability = connection.speech_to_text.capability
    source = Map.new(identity)
    onset = %Signal{kind: :turn_started, provider_sequence: 1, text: ""}
    final = %{onset | kind: :turn_ended, provider_sequence: 2, text: "Unknown source interval"}
    send(room, {:vxpipe_stt_signal, capability, source, onset})
    send(room, {:vxpipe_stt_signal, capability, source, final})
    assert_receive {:vxpipe_event, %CallEngine.Event.ParticipantTurnStarted{correlation_id: turn}}

    assert_receive {:vxpipe_event, %CallEngine.Event.AgentTurnFailed{correlation_id: ^turn}},
                   2_000

    refute_received {:gate, _, _, _}
    refute_received {:test_agent_runtime_stream, _, _}
  end

  test "a submitted interrupted input may report tokens without reopening model admission" do
    plan = guarded_plan(true)
    {_room, identity} = start_guarded_call(plan, controlled_decisions(self()))
    id = plan.participants["agent"].participant_id
    send_turn(identity, "cancelled", "First input.")
    late = assert_held(id, "First input.")
    send_turn(identity, "replacement", "New input.")
    replacement = assert_held(id, "New input.")

    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_evaluation,
                      payload: %{
                        "source_turn_id" => "cancelled",
                        "outcome" => "cancelled",
                        "attempt_ids" => [attempt]
                      }
                    }},
                   2_000

    assert_receive {:test_archive_fact,
                    %{
                      kind: :decisions_attempt,
                      id: ^attempt,
                      payload: %{"outcome" => "cancelled"}
                    }}

    send(late, {:score, 0.9})

    assert_receive {:test_archive_fact,
                    %{
                      kind: :usage_observed,
                      payload: %{
                        "attempt_id" => ^attempt,
                        "measurement" => %{
                          "component" => "total_tokens",
                          "quantity" => 7,
                          "status" => "correction"
                        }
                      }
                    }},
                   2_000

    refute_received {:test_agent_runtime_stream, _, _}
    send(replacement, {:score, 0.9})
    assert_receive {:test_agent_runtime_stream, _, model}, 2_000
    assert Enum.any?(model.messages, &String.contains?(&1.content, "New input."))
    refute Enum.any?(model.messages, &String.contains?(&1.content, "First input."))

    refute_received {:test_archive_fact,
                     %{
                       kind: :decisions_evaluation,
                       payload: %{"source_turn_id" => "cancelled", "outcome" => "passed"}
                     }}
  end
end
