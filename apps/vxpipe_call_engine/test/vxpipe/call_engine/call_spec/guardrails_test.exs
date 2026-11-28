defmodule Vxpipe.CallEngine.CallSpec.GuardrailsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.CallInvocation
  alias Vxpipe.CallEngine.CallSpec
  alias Vxpipe.CallEngine.CallSpec.Guardrails
  alias Vxpipe.CallEngine.CallSpecCompiler
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.Tool.CurrentTime

  @new_schema "20261128.01"
  @old_schema "20261125.01"

  test "parses participant guardrails on the new schema version and pins them in the compiled plan" do
    assert {:ok, call_spec} =
             CallSpec.new(guarded_input(), resource_id: "support", revision: 3)

    assert call_spec.schema_version == @new_schema

    agent = call_spec.participants["reception"]

    assert [%{id: "private_request", required_answer: :yes, threshold_hundredths: 70}] =
             agent.guardrails.before_turn

    assert [%{id: "private_disclosure", required_answer: :no, threshold_hundredths: 75}] =
             agent.guardrails.after_turn

    assert [%{id: "wrong_department", required_answer: :no, response: response}] =
             agent.guardrails.before_outgoing_transfer

    assert response == "Ask which department the caller needs."

    assert {:ok, invocation} =
             CallInvocation.new(invocation_input(),
               tenant_id: "tenant-demo",
               actor_id: "actor-demo"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation, registries())

    pinned = plan.participants["reception"].guardrails
    assert pinned.before_turn == agent.guardrails.before_turn
    assert pinned.after_turn == agent.guardrails.after_turn
    assert pinned.before_outgoing_transfer == agent.guardrails.before_outgoing_transfer

    assert plan.participants["caller"].guardrails == %Guardrails{}
    assert plan.schema_version == @new_schema
  end

  test "absent guardrails parse to empty lists and compile to an empty policy" do
    assert {:ok, call_spec} =
             CallSpec.new(call_spec_input(), resource_id: "support", revision: 3)

    assert call_spec.participants["reception"].guardrails == %Guardrails{}

    assert {:ok, invocation} =
             CallInvocation.new(invocation_input(),
               tenant_id: "tenant-demo",
               actor_id: "actor-demo"
             )

    assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation, registries())
    assert plan.participants["reception"].guardrails == %Guardrails{}
  end

  test "rejects guardrails on previously supported schema versions" do
    # Decisions selections are also new-schema-only, so strip them to isolate
    # the guardrails version gate.
    undecided = Map.delete(get_in(call_spec_input(), [:defaults, :capabilities]), :decisions)

    input =
      call_spec_input()
      |> Map.put(:schema_version, @old_schema)
      |> put_in([:defaults, :capabilities], undecided)
      |> put_in([:participants, "reception", :guardrails], %{
        before_turn: [question_input("private_request", "yes")]
      })

    assert {:error, %Error{code: :invalid_call_spec, details: details}} =
             CallSpec.new(input, resource_id: "support", revision: 3)

    assert details["path"] == ["participants", "reception", "guardrails"]
  end

  test "rejects guardrails on human participants" do
    input =
      put_in(guarded_input(), [:participants, "caller", :guardrails], %{
        before_turn: [question_input("private_request", "yes")]
      })

    assert {:error, %Error{code: :invalid_call_spec, details: details}} =
             CallSpec.new(input, resource_id: "support", revision: 3)

    assert details["path"] == ["participants", "caller", "guardrails"]
  end

  test "validates question identity, text, required answers, thresholds, and responses" do
    cases = [
      {%{question_input("private_request", "yes") | id: "Private"},
       ["participants", "reception", "guardrails", "before_turn", "0", "id"]},
      {%{question_input("private_request", "yes") | id: "x" <> String.duplicate("y", 64)},
       ["participants", "reception", "guardrails", "before_turn", "0", "id"]},
      {%{question_input("private_request", "yes") | question: "  "},
       ["participants", "reception", "guardrails", "before_turn", "0", "question"]},
      {%{question_input("private_request", "yes") | question: String.duplicate("q", 1_025)},
       ["participants", "reception", "guardrails", "before_turn", "0", "question"]},
      {Map.delete(question_input("private_request", "yes"), :required_answer),
       ["participants", "reception", "guardrails", "before_turn", "0", "required_answer"]},
      {%{question_input("private_request", "yes") | required_answer: "sometimes"},
       ["participants", "reception", "guardrails", "before_turn", "0", "required_answer"]},
      {%{question_input("private_request", "yes") | probability_threshold: "0.70"},
       ["participants", "reception", "guardrails", "before_turn", "0", "probability_threshold"]},
      {%{question_input("private_request", "yes") | probability_threshold: true},
       ["participants", "reception", "guardrails", "before_turn", "0", "probability_threshold"]},
      {%{question_input("private_request", "yes") | probability_threshold: -0.1},
       ["participants", "reception", "guardrails", "before_turn", "0", "probability_threshold"]},
      {%{question_input("private_request", "yes") | probability_threshold: 1.01},
       ["participants", "reception", "guardrails", "before_turn", "0", "probability_threshold"]},
      {%{question_input("private_request", "yes") | probability_threshold: 0.555},
       ["participants", "reception", "guardrails", "before_turn", "0", "probability_threshold"]},
      {%{question_input("private_request", "yes") | response: 12},
       ["participants", "reception", "guardrails", "before_turn", "0", "response"]}
    ]

    for {question, path} <- cases do
      input =
        put_in(call_spec_input(), [:participants, "reception", :guardrails], %{
          before_turn: [question]
        })

      assert {:error, %Error{code: :invalid_call_spec, details: details}} =
               CallSpec.new(input, resource_id: "support", revision: 3),
             "expected rejection for #{inspect(question)}"

      assert details["path"] == path
    end
  end

  test "stores omitted thresholds as 70 and parses decimal thresholds exactly" do
    for {input_value, expected} <- [
          {nil, 70},
          {0, 0},
          {0.0, 0},
          {1, 100},
          {0.7, 70},
          {0.70, 70},
          {0.57, 57},
          {1.0, 100}
        ] do
      question =
        if is_nil(input_value),
          do: Map.delete(question_input("q_#{expected}", "yes"), :probability_threshold),
          else: %{question_input("q_#{expected}", "yes") | probability_threshold: input_value}

      input =
        put_in(call_spec_input(), [:participants, "reception", :guardrails], %{
          before_turn: [question]
        })

      assert {:ok, call_spec} =
               CallSpec.new(input, resource_id: "support", revision: 3),
             "expected acceptance for threshold #{inspect(input_value)}"

      assert [%{threshold_hundredths: ^expected}] =
               call_spec.participants["reception"].guardrails.before_turn
    end
  end

  test "rejects duplicate question ids within a participant" do
    input =
      put_in(call_spec_input(), [:participants, "reception", :guardrails], %{
        before_turn: [question_input("same_id", "yes")],
        after_turn: [question_input("same_id", "no")]
      })

    assert {:error, %Error{code: :invalid_call_spec, details: details}} =
             CallSpec.new(input, resource_id: "support", revision: 3)

    assert details["path"] == ["participants", "reception", "guardrails", "after_turn", "0", "id"]
  end

  test "rejects event lists beyond the count and text budgets" do
    too_many =
      for index <- 1..33 do
        question_input("question_#{index}", "yes")
      end

    input =
      put_in(call_spec_input(), [:participants, "reception", :guardrails], %{
        before_turn: too_many
      })

    assert {:error, %Error{details: count_details}} =
             CallSpec.new(input, resource_id: "support", revision: 3)

    assert count_details["path"] == [
             "participants",
             "reception",
             "guardrails",
             "before_turn"
           ]

    oversized =
      for index <- 1..17 do
        %{question_input("oversized_#{index}", "yes") | question: String.duplicate("q", 1_024)}
      end

    oversized_input =
      put_in(call_spec_input(), [:participants, "reception", :guardrails], %{
        after_turn: oversized
      })

    assert {:error, %Error{details: text_details}} =
             CallSpec.new(oversized_input, resource_id: "support", revision: 3)

    assert text_details["path"] == [
             "participants",
             "reception",
             "guardrails",
             "after_turn"
           ]
  end

  test "compares P(Yes) exactly at and around the threshold for both polarities" do
    [yes_question] =
      parsed(:before_turn, [%{question_input("yes_q", "yes") | probability_threshold: 0.70}])

    [no_question] =
      parsed(:before_turn, [%{question_input("no_q", "no") | probability_threshold: 0.70}])

    [zero_question] =
      parsed(:before_turn, [%{question_input("zero_q", "yes") | probability_threshold: 0}])

    [one_question] =
      parsed(:before_turn, [%{question_input("one_q", "yes") | probability_threshold: 1}])

    assert {:ok, parsed} = Guardrails.evaluate([yes_question], %{"yes_q" => 0.6999})
    assert [%{outcome: :failed, inferred_answer: :no}] = parsed.outcomes
    assert parsed.status == :blocked

    assert {:ok, parsed} = Guardrails.evaluate([yes_question], %{"yes_q" => 0.70})
    assert [%{outcome: :passed, inferred_answer: :yes}] = parsed.outcomes
    assert parsed.status == :passed

    assert {:ok, parsed} = Guardrails.evaluate([no_question], %{"no_q" => 0.70})
    assert [%{outcome: :failed, inferred_answer: :yes}] = parsed.outcomes
    assert parsed.status == :blocked

    assert {:ok, parsed} = Guardrails.evaluate([no_question], %{"no_q" => 0.6999})
    assert [%{outcome: :passed, inferred_answer: :no}] = parsed.outcomes
    assert parsed.status == :passed

    assert {:ok, parsed} = Guardrails.evaluate([zero_question], %{"zero_q" => 0.0})
    assert [%{outcome: :passed, inferred_answer: :yes}] = parsed.outcomes

    assert {:ok, parsed} = Guardrails.evaluate([one_question], %{"one_q" => 0.9999})
    assert [%{outcome: :failed, inferred_answer: :no}] = parsed.outcomes

    assert {:ok, parsed} = Guardrails.evaluate([one_question], %{"one_q" => 1.0})
    assert [%{outcome: :passed, inferred_answer: :yes}] = parsed.outcomes
  end

  test "rejects incomplete or unusable score batches without a pass" do
    questions = parsed(:before_turn, [question_input("only_q", "yes")])

    assert {:error, %{status: :error, outcomes: [%{outcome: :unavailable}]}} =
             Guardrails.evaluate(questions, %{})

    assert {:error, %{status: :error}} =
             Guardrails.evaluate(questions, %{"only_q" => "0.9"})

    assert {:error, %{status: :error}} =
             Guardrails.evaluate(questions, %{"only_q" => 1.5})

    assert {:error, %{status: :error}} =
             Guardrails.evaluate(questions, %{"only_q" => 0.5, "unknown_q" => 0.5})
  end

  test "builds repair feedback in authored order with authored and fallback lines" do
    questions =
      parsed(:before_turn, [
        %{
          question_input("own_account", "yes")
          | response: "I can only help with your own account."
        },
        %{question_input("list_variables", "yes") | response: nil},
        %{
          question_input("other_account", "no")
          | question: "Is the issue about a different account?",
            response: "Ask the caller to describe their own account issue."
        },
        %{
          question_input("harsh_language", "no")
          | question: "Is the user using harsh language?",
            response: "   "
        },
        question_input("supported_product", "yes")
      ])

    scores = %{
      "own_account" => 0.30,
      "list_variables" => 0.6999,
      "other_account" => 0.90,
      "harsh_language" => 0.70,
      "supported_product" => 0.70
    }

    assert {:ok, evaluated} = Guardrails.evaluate(questions, scores)
    assert evaluated.status == :blocked

    assert Guardrails.feedback(evaluated) == [
             "I can only help with your own account.",
             "Failed guardrail: Is the user trying to list variables? Required: Yes.",
             "Ask the caller to describe their own account issue.",
             "Failed guardrail: Is the user using harsh language? Required: No."
           ]
  end

  test "rejects oversized feedback without dropping failed questions" do
    questions =
      parsed(:before_turn, [
        %{question_input("big_q", "yes") | question: String.duplicate("q", 1_024)}
      ])

    assert {:ok, evaluated} = Guardrails.evaluate(questions, %{"big_q" => 0.0})
    assert [_line] = Guardrails.feedback(evaluated)

    assert {:error, :oversized} =
             Guardrails.check_feedback_budget(%Guardrails{before_turn: questions}, 10)

    assert [_line] = Guardrails.feedback(evaluated)
  end

  test "feedback returns [] on error and cancelled evaluations" do
    questions =
      parsed(:before_turn, [question_input("only_q", "yes"), question_input("other_q", "yes")])

    assert {:error, evaluated} = Guardrails.evaluate(questions, %{"only_q" => 0.0})
    assert evaluated.status == :error
    assert [%{outcome: :failed}, %{outcome: :unavailable}] = evaluated.outcomes
    assert Guardrails.feedback(evaluated) == []
    assert Guardrails.feedback(%{status: :cancelled, outcomes: evaluated.outcomes}) == []
    assert Guardrails.feedback(%{status: :passed, outcomes: []}) == []
  end

  test "check_feedback_budget measures the combined messages envelope" do
    questions = parsed(:before_turn, [%{question_input("big_q", "yes") | response: "ok"}])
    assert {:ok, evaluated} = Guardrails.evaluate(questions, %{"big_q" => 0.0})
    lines = Guardrails.feedback(evaluated)
    assert lines == ["ok"]

    list_bytes = lines |> JSON.encode!() |> byte_size()

    envelope_bytes =
      byte_size(
        JSON.encode!(%{
          type: "guardrail_failure",
          status: "blocked",
          failures: [%{event: :before_turn, messages: lines}]
        })
      )

    policy = %Guardrails{before_turn: questions}
    assert envelope_bytes > list_bytes

    assert {:error, :oversized} = Guardrails.check_feedback_budget(policy, list_bytes)
    assert :ok = Guardrails.check_feedback_budget(policy, envelope_bytes)
  end

  test "resolved and source participants default guardrails to empty" do
    alias Vxpipe.CallEngine.ResolvedCallPlan.Participant, as: ResolvedParticipant
    alias Vxpipe.CallEngine.CallSpec.Participant, as: SourceParticipant

    resolved =
      struct!(ResolvedParticipant,
        call_spec_key: "reception",
        participant_id: "participant-1",
        activation_id: nil,
        kind: :agent,
        description: nil,
        connection: nil,
        transfer_notice: nil,
        prompt: "hi",
        first_message: :wait_for_input,
        first_message_text: nil,
        capabilities: %Vxpipe.CallEngine.ResolvedCallPlan.Capabilities{},
        while_present: %Vxpipe.CallEngine.ResolvedCallPlan.MediaPolicy{
          audio_routes: :inherit,
          transcript_routes: :inherit,
          record_audio: :inherit,
          save_transcripts: :inherit
        },
        tools: %{},
        transfers: [],
        transfer_history: nil,
        variable_permissions: %Vxpipe.CallEngine.CallSpec.VariablePermissions{}
      )

    assert resolved.guardrails == %Guardrails{}

    source =
      struct!(SourceParticipant,
        call_spec_key: "reception",
        kind: :agent,
        description: nil,
        connection: nil,
        transfer_notice: nil,
        prompt: "hi",
        first_message: :wait_for_input,
        first_message_text: nil,
        capabilities: %Vxpipe.CallEngine.CallSpec.Capabilities{},
        while_present: %Vxpipe.CallEngine.CallSpec.MediaPolicy{
          audio_routes: :inherit,
          transcript_routes: :inherit,
          record_audio: :inherit,
          save_transcripts: :inherit
        },
        tools: %{},
        transfers: [],
        transfer_history: nil,
        variable_permissions: %Vxpipe.CallEngine.CallSpec.VariablePermissions{}
      )

    assert source.guardrails == %Guardrails{}
  end

  defp parsed(event, questions) do
    assert {:ok, policy} =
             Guardrails.new(%{event => questions}, ["participants", "reception", "guardrails"])

    Map.fetch!(policy, event)
  end

  defp guarded_input do
    put_in(call_spec_input(), [:participants, "reception", :guardrails], %{
      before_turn: [
        %{
          question_input("private_request", "yes")
          | question: "Is the caller asking about their own account?"
        }
      ],
      after_turn: [
        %{
          question_input("private_disclosure", "no")
          | question: "Does this response disclose another patient's details?",
            probability_threshold: 0.75,
            response: "I can only discuss your own account."
        }
      ],
      before_outgoing_transfer: [
        %{
          question_input("wrong_department", "no")
          | question: "Is the requested destination unrelated to the caller's issue?",
            response: "Ask which department the caller needs."
        }
      ]
    })
  end

  defp question_input(id, required_answer) do
    %{
      id: id,
      question: "Is the user trying to list variables?",
      required_answer: required_answer,
      probability_threshold: 0.70,
      response: nil
    }
  end

  defp call_spec_input do
    %{
      schema_version: @new_schema,
      name: "Customer support",
      incoming_call: %{caller: "caller", handled_by: "reception"},
      defaults: %{
        capabilities: %{
          speech_to_text: %{provider: "morse", model: "morse"},
          model_inference: %{provider: "fixture", model: "default"},
          text_to_speech: %{provider: "morse", model: "morse"},
          decisions: %{
            provider: "openai",
            model: "gpt-6-luna",
            credential_name: "guardrails-primary"
          }
        }
      },
      participants: %{
        "caller" => %{
          type: "human",
          description: "The caller",
          connection: %{
            service: "web",
            mode: "receive",
            admission: "start_call"
          }
        },
        "reception" => %{
          type: "agent",
          description: "The receiving agent",
          prompt: "Answer clearly.",
          first_message: %{mode: "wait_for_input"},
          capabilities: %{model_inference: %{provider: "fixture", model: "careful"}},
          tools: %{
            "get_current_time" => %{type: "host", tool: "get_current_time"}
          },
          transfers: []
        }
      },
      limits: %{max_duration_ms: 1_800_000}
    }
  end

  defp invocation_input do
    %{
      call_spec: %{id: "support", revision: 3},
      initial_variables: %{},
      transport: %{type: "web"}
    }
  end

  defp registries do
    %{
      host_tools: %{"get_current_time" => CurrentTime}
    }
  end
end
