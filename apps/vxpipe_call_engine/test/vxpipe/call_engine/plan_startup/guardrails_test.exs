defmodule Vxpipe.CallEngine.PlanStartup.GuardrailsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{AgentActivationSupervisor, CallInvocation, CallSpec, CallSpecCompiler}
  alias Vxpipe.CallEngine.Guardrails.Participant
  alias Vxpipe.CallEngine.PlanStartup.AgentActivation
  alias Vxpipe.CallEngine.{TestAgentRuntimeModelProvider, TestTenantCredentialSource}

  test "compiled participant checks use the pinned Decisions provider and selected tenant binding" do
    plan = compile_plan(true)
    participant = Map.fetch!(plan.participants, "agent")
    observer = self()

    plug = fn conn ->
      body = JSON.decode!(Req.Test.raw_body(conn))

      send(
        observer,
        {:provider, conn.request_path, Plug.Conn.get_req_header(conn, "authorization"), body}
      )

      Req.Test.json(conn, %{
        model: "gpt-6-luna",
        answers: [%{name: "scope", type: "predicate", probability: 0.2}]
      })
    end

    bindings = %{{"tenant", "openai", "policy"} => %{"api_key" => "synthetic-policy-key"}}

    assert {:ok, activation_options} =
             AgentActivation.new(plan, participant, options(bindings, plug))

    assert activation_options[:guardrails][:maximum_pending_requests] == 3
    activation = start_supervised!({AgentActivationSupervisor, activation_options})
    assert %{guardrails: service} = AgentActivationSupervisor.children(activation)

    assert {:blocked, ["Please ask about a supported product."]} =
             Participant.check(
               service,
               :before_turn,
               "proposal",
               %{"text" => "Hello"},
               System.monotonic_time(:millisecond) + 2_000
             )

    assert_received {:tenant_credential_resolved, "tenant", "openai", "policy"}
    assert_received {:provider, "/v1/decisions", ["Bearer synthetic-policy-key"], body}
    assert body["model"] == "gpt-6-luna"

    assert [%{"name" => "scope", "instructions" => "Is this supported?", "type" => "predicate"}] ==
             body["questions"]

    assert %{"event" => "before_turn", "current" => %{"text" => "Hello"}} =
             JSON.decode!(body["input"])

    refute JSON.encode!(body) =~ "Please ask"
    refute JSON.encode!(body) =~ "required_answer"
  end

  test "Decisions sends separately labeled bounded context and current evidence to the selected provider" do
    plan = compile_plan(true)
    participant = plan.participants["agent"]
    owner = self()

    plug = fn conn ->
      send(owner, {:posted, JSON.decode!(Req.Test.raw_body(conn))})

      Req.Test.json(conn, %{
        model: "gpt-6-luna",
        answers: [%{name: "scope", type: "predicate", probability: 0.9}]
      })
    end

    bindings = %{{"tenant", "openai", "policy"} => %{"api_key" => "synthetic-policy-key"}}

    {:ok, [guardrails: settings]} =
      Vxpipe.CallEngine.PlanStartup.Guardrails.options(plan, participant, options(bindings, plug))

    adapter = Keyword.fetch!(settings, :adapter)
    old = String.duplicate("o", 8192)
    message = fn text -> %{"participant_id" => "caller", "text" => text} end

    current = %{
      "text" => "A reply.",
      "proposed_calls" => [
        %{"name" => "lookup", "kind" => "ordinary", "arguments" => %{"key" => "secret"}}
      ],
      "triggering_input" => message.("Latest input"),
      "recent_context" => %{
        "messages" => Enum.map([old, "b", "c", "d", "e"], message),
        "omitted" => false
      },
      "internal_field" => "hidden",
      "correlation" => %{"source_participant_id" => participant.participant_id}
    }

    request = %{
      event: :after_turn,
      evidence: current,
      questions: [%{id: "scope", question: "Allowed?"}],
      deadline: System.monotonic_time(:millisecond) + 2000
    }

    assert {:ok, _} = adapter.(request)
    assert_receive {:posted, %{"input" => encoded}}
    input = JSON.decode!(encoded)

    assert input["current"] == %{
             "text" => "A reply.",
             "proposed_calls" => [%{"name" => "lookup", "kind" => "ordinary"}]
           }

    assert input["recent_context"] == %{
             "messages" => Enum.map(["b", "c", "d", "e"], message),
             "omitted" => true
           }

    assert input["triggering_input"] == message.("Latest input")
    assert input["source_participant_id"] == participant.participant_id
    refute encoded =~ "secret"
    refute encoded =~ "hidden"

    oversized_history = %{"messages" => [message.(old), message.("keep")], "omitted" => false}

    assert {:ok, _} =
             adapter.(%{
               request
               | evidence: Map.put(current, "recent_context", oversized_history)
             })

    assert_receive {:posted, %{"input" => encoded}}

    assert JSON.decode!(encoded)["recent_context"] == %{
             "messages" => [message.("keep")],
             "omitted" => true
           }

    assert {:error, :oversized} =
             adapter.(%{
               request
               | evidence:
                   Map.put(current, "triggering_input", message.(String.duplicate("x", 8193)))
             })

    refute_received {:posted, _}
    assert {:ok, _} = adapter.(%{request | evidence: %{"text" => "Only current"}})
    assert_receive {:posted, %{"input" => encoded}}
    assert JSON.decode!(encoded)["recent_context"] == %{"messages" => [], "omitted" => true}
  end

  test "policy identity preserves the event and order of authored questions" do
    plan = compile_plan(true)
    participant = plan.participants["agent"]
    policy = participant.guardrails
    [first] = policy.before_turn
    second = %{first | id: "second"}
    bindings = %{{"tenant", "openai", "policy"} => %{"api_key" => "synthetic-policy-key"}}

    digest = fn before_turn, after_turn ->
      participant = %{
        participant
        | guardrails: %{policy | before_turn: before_turn, after_turn: after_turn}
      }

      {:ok, [guardrails: settings]} =
        Vxpipe.CallEngine.PlanStartup.Guardrails.options(
          plan,
          participant,
          options(bindings, nil)
        )

      Keyword.fetch!(settings, :policy_digest)
    end

    original = digest.([first, second], [])
    assert original == digest.([first, second], [])
    refute original == digest.([second, first], [])
    refute original == digest.([first], [second])
  end

  test "startup checks the worst-case grouped feedback against the configured model budget" do
    plan = compile_plan(true)
    participant = plan.participants["agent"]
    [first] = participant.guardrails.before_turn
    second = %{first | id: "destination", response: nil}

    policy = %{
      participant.guardrails
      | after_turn: [first],
        before_turn: [],
        before_outgoing_transfer: [second]
    }

    participant = %{participant | guardrails: policy}
    bindings = %{{"tenant", "openai", "policy"} => %{"api_key" => "synthetic-policy-key"}}

    feedback = %{
      type: "guardrail_failure",
      status: "blocked",
      failures: [
        %{event: :after_turn, messages: [first.response]},
        %{
          event: :before_outgoing_transfer,
          messages: ["Failed guardrail: Is this supported? Required: Yes."]
        }
      ]
    }

    bytes = byte_size(JSON.encode!(feedback))

    start = fn limit ->
      opts =
        Keyword.update!(
          options(bindings, nil),
          :agent_runtime,
          &Keyword.put(&1, :maximum_model_context_bytes, limit)
        )

      AgentActivation.new(plan, participant, opts)
    end

    assert {:error, %{details: %{"path" => ["participants", "agent", "guardrails"]}}} =
             start.(bytes - 1)

    refute_received {:tenant_credential_resolved, "tenant", "openai", "policy"}
    assert {:ok, _settings} = start.(bytes)
  end

  test "missing required Decisions credentials fail activation at the Decisions field" do
    plan = compile_plan(true)

    assert {:error, %{details: %{"path" => ["defaults", "capabilities", "decisions"]}}} =
             AgentActivation.new(plan, plan.participants["agent"], options(%{}, nil))
  end

  test "participants without checks skip credential lookup and Guardrails startup" do
    plan = compile_plan(false)

    assert {:ok, settings} =
             AgentActivation.new(plan, plan.participants["agent"], options(%{}, nil))

    refute Keyword.has_key?(settings, :guardrails)
    refute_received {:tenant_credential_resolved, _, _, _}
  end

  test "a native speech activation owns its outgoing transfer guardrails" do
    alias Vxpipe.CallEngine.{PlanStartup, RoomCapabilitySupervisor, TestAudioOutputSink}

    plan = compile_plan(true, :native)
    bindings = %{{"tenant", "openai", "policy"} => %{"api_key" => "synthetic-policy-key"}}

    plug = fn conn ->
      Req.Test.json(conn, %{
        model: "gpt-6-luna",
        answers: [%{name: "scope", type: "predicate", probability: 0.2}]
      })
    end

    assert {:ok, startup} = PlanStartup.new(plan, native_options(bindings, plug))
    assert %{guardrails: guardrail_settings} = runtime = startup.speech_to_speech
    assert guardrail_settings[:maximum_pending_requests] == 3
    assert startup.agent_activation == nil
    incarnation = "sts-guardrail-#{System.unique_integer([:positive])}"
    start_supervised!({RoomCapabilitySupervisor, incarnation_id: incarnation})
    sink = start_supervised!({TestAudioOutputSink, observer: self()})

    assert {:ok, _capability} =
             RoomCapabilitySupervisor.start_speech_to_speech(incarnation,
               owner: self(),
               activation_id: runtime.activation_id,
               agent_id: runtime.participant_id,
               human_id: startup.caller.participant_id,
               provider: runtime.provider,
               provider_private: runtime.provider_private,
               sink: sink,
               frame_identity: %{},
               caller_source: :sts,
               policy: %Vxpipe.CallEngine.MediaPolicy.Effective{
                 audio_routes: :unrestricted,
                 transcript_routes: :unrestricted,
                 record_audio: false,
                 save_transcripts: false
               },
               guardrails: guardrail_settings
             )

    service = AgentActivationSupervisor.child_ref(runtime.activation_id, :guardrails)
    deadline = System.monotonic_time(:millisecond) + 2_000
    assert :passed = Participant.check(service, :after_turn, "native", %{}, deadline)

    assert {:blocked, ["Please ask about a supported product."]} =
             Participant.check(
               service,
               :before_outgoing_transfer,
               "handoff",
               %{"destination" => "reception"},
               deadline
             )
  end

  test "native startup reports an unavailable Decisions binding at the call-wide selection" do
    plan = compile_plan(true, :native)

    assert {:error, %{details: %{"path" => ["defaults", "capabilities", "decisions"]}}} =
             Vxpipe.CallEngine.PlanStartup.new(plan, native_options(%{}, nil))
  end

  defp native_options(bindings, plug) do
    options(bindings, plug) ++
      [
        speech_to_text: [providers: %{}],
        text_to_speech: [providers: %{}],
        speech_to_speech: [
          providers: %{Vxpipe.Providers.MorseCode.DuplexSTSSession => [enabled: true]}
        ]
      ]
  end

  defp options(bindings, plug) do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    runtime =
      settings
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.merge(
        fixture: {TestAgentRuntimeModelProvider, [owner: self()]},
        maximum_pending_requests: 3,
        decisions_http_plug: plug
      )

    [
      owner: self(),
      agent_runtime: runtime,
      credential_source: {TestTenantCredentialSource, {self(), bindings}}
    ]
  end

  defp compile_plan(guarded?, mode \\ :llm) do
    questions =
      if guarded?,
        do: [
          %{
            id: "scope",
            question: "Is this supported?",
            required_answer: "yes",
            response: "Please ask about a supported product."
          }
        ],
        else: []

    source = %{
      schema_version: "20261128.01",
      name: "Guarded startup",
      incoming_call: %{caller: "caller", handled_by: "agent"},
      defaults: %{
        capabilities: %{
          speech_to_text: %{provider: "morse", model: "morse"},
          text_to_speech: %{provider: "morse", model: "morse"},
          model_inference: %{provider: "fixture", model: "default"},
          decisions: %{provider: "openai", model: "gpt-6-luna", credential_name: "policy"}
        }
      },
      participants: %{
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
          guardrails: %{before_turn: questions}
        }
      }
    }

    source =
      if mode == :native do
        source
        |> update_in([:defaults, :capabilities], &Map.take(&1, [:decisions]))
        |> put_in([:participants, "agent", :capabilities], %{
          speech_to_speech: %{provider: "morse", model: "morse-duplex"}
        })
        |> put_in([:participants, "agent", :guardrails], %{before_outgoing_transfer: questions})
      else
        source
      end

    {:ok, spec} = CallSpec.new(source, resource_id: "support", revision: 3)

    {:ok, invocation} =
      CallInvocation.new(%{call_spec: %{id: "support", revision: 3}, transport: %{type: "web"}},
        tenant_id: "tenant",
        actor_id: "operator"
      )

    {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
    plan
  end
end
