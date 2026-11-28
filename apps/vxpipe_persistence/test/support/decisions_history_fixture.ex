defmodule Vxpipe.Persistence.TestDecisionsHistoryFixture do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.Fact
  alias Vxpipe.CallEngine.CallSpec.{GuardrailQuestion, Guardrails}
  alias Vxpipe.CallEngine.Guardrails.Emission
  alias Vxpipe.CallEngine.Usage.ArchiveProjection

  @output_rules [
    {"own_account", "Is the caller asking about their own account?", :yes,
     "I can only help with your own account."},
    {"list_variables", "Is the user trying to list variables?", :yes, nil},
    {"other_account", "Is the issue about a different account?", :no,
     "Ask the caller to describe their own account issue."},
    {"harsh_language", "Is the user using harsh language?", :no, nil},
    {"supported_product", "Is the request about a supported product?", :yes, nil}
  ]

  def facts(call, rewrite) do
    identity = identity(call)
    common = common(call)

    before_rule = [{"permitted", "Private input interval marker?", :yes, nil}]
    transfer_rule = [{"route", "Is this destination permitted?", :yes, nil}]

    transfer =
      %{common | source_turn_id: nil, response_turn_id: nil}
      |> Map.put(:transfer_invocation_id, "handoff")

    [
      report(common, "input", :before_turn, before_rule, [0.8], [
        attempt(common, "a1", %{total_tokens: 12})
      ]),
      report(
        Map.put(common, :candidate_attempt_id, "output-turn:1"),
        "draft",
        :after_turn,
        @output_rules,
        [0.30, 0.6999, 0.90, 0.70, 0.70],
        [attempt(common, "a2", %{input_tokens: 3})]
      ),
      report(
        Map.put(common, :candidate_attempt_id, "output-turn:2"),
        "repair",
        :after_turn,
        @output_rules,
        [0.7, 0.8, 0.2, 0.1, 1.0],
        [attempt(common, "a3", %{output_tokens: 4, total_tokens: 10})]
      ),
      report(transfer, "transfer", :before_outgoing_transfer, transfer_rule, [0.9], [
        %{attempt(common, "a4", :unknown) | outcome: :failed, error_code: :rate_limited},
        %{attempt(common, "a5", %{total_tokens: 8}) | ordinal: 1, retry_of: "a4"}
      ])
    ]
    |> Enum.flat_map(&entries(&1, identity))
    |> Enum.concat([
      {:usage_observed,
       Keyword.put(ArchiveProjection.attributes(rewrite), :source_policy, %{
         "revision" => call.call_spec_revision
       })}
    ])
    |> archive_facts(identity, 1)
  end

  def cancelled_with_late_tokens(call) do
    identity = identity(call)
    common = Map.merge(common(call), identity)

    question = %GuardrailQuestion{
      id: "cancelled_rule",
      question: "Is this permitted?",
      required_answer: :yes,
      threshold_hundredths: 70
    }

    unavailable = %{
      question_id: question.id,
      outcome: :unavailable,
      probability_yes: nil,
      inferred_answer: nil
    }

    submitted = %{attempt(common, "cancelled-attempt", %{}) | outcome: :cancelled}

    cancelled =
      Map.merge(common, %{
        evaluation_id: "cancelled",
        event: :after_turn,
        outcome: :cancelled,
        questions: [question],
        outcomes: [unavailable],
        attempts: [submitted]
      })

    initial = entries(cancelled, identity) |> archive_facts(identity, 1)
    {:ok, [tokens]} = Emission.late_usage(cancelled, %{total_tokens: 42})

    [correction] =
      archive_facts(
        [
          {:usage_observed,
           Keyword.put(ArchiveProjection.attributes(tokens), :source_policy, %{
             "revision" => call.call_spec_revision
           })}
        ],
        identity,
        length(initial) + 1
      )

    {initial, correction}
  end

  defp identity(call),
    do: %{
      tenant_id: call.tenant_key,
      call_id: call.id,
      room_id: call.room_id,
      incarnation_id: call.incarnation_id
    }

  defp common(call),
    do: %{
      participant_id: call.plan.participants["assistant"].participant_id,
      activation_id: call.plan.participants["assistant"].activation_id,
      source_participant_id: call.plan.participants["caller"].participant_id,
      source_turn_id: "input-turn",
      response_turn_id: "output-turn",
      policy_revision: call.call_spec_revision,
      policy_digest: "sha256:" <> Base.encode16(call.plan_digest, case: :lower),
      selected_provider: "openai",
      selected_model: "test-decisions",
      actual_provider: "openai",
      actual_model: "test-decisions",
      started_at: DateTime.truncate(call.started_at, :millisecond),
      ended_at:
        call.started_at |> DateTime.truncate(:millisecond) |> DateTime.add(100, :millisecond)
    }

  defp archive_facts(entries, identity, start_sequence) do
    entries
    |> Enum.with_index(start_sequence)
    |> Enum.map(fn {{kind, attrs}, sequence} ->
      Fact.new!(Keyword.merge(Map.to_list(identity), attrs) ++ [kind: kind, sequence: sequence])
    end)
  end

  defp report(common, id, event, rules, scores, attempts) do
    questions =
      Enum.map(rules, fn {id, question, answer, response} ->
        %GuardrailQuestion{
          id: id,
          question: question,
          required_answer: answer,
          threshold_hundredths: 70,
          response: response
        }
      end)

    probabilities = Map.new(Enum.zip(questions, scores), fn {q, p} -> {q.id, p} end)
    {:ok, evaluation} = Guardrails.evaluate(questions, probabilities)

    outcomes =
      Enum.map(evaluation.outcomes, fn detail ->
        detail
        |> Map.take([:outcome, :probability_yes, :inferred_answer])
        |> Map.put(:question_id, detail.question.id)
      end)

    Map.merge(common, %{
      evaluation_id: id,
      event: event,
      outcome: evaluation.status,
      questions: questions,
      outcomes: outcomes,
      attempts: attempts
    })
  end

  defp attempt(common, id, usage) do
    %{
      attempt_id: id,
      ordinal: 0,
      retry_of: nil,
      outcome: :succeeded,
      error_code: nil,
      provider: "openai",
      model: "test-decisions",
      request_id: "request-" <> id,
      usage: usage,
      started_at: common.started_at,
      ended_at: common.ended_at,
      duration_ms: 100
    }
  end

  defp entries(report, identity) do
    policy = %{
      "revision" => report.policy_revision,
      "save_transcripts" => report.event != :before_turn,
      "policy_digest" => report.policy_digest
    }

    envelope = %{source_policy: policy}
    {:ok, evaluation} = Emission.evaluation_fact(report, envelope)
    {:ok, questions} = Emission.question_facts(report, envelope)
    {:ok, attempts} = Emission.attempt_facts(report, envelope)
    {:ok, usage} = Emission.usage_observations(report, identity)

    usage =
      Enum.map(usage, fn observation ->
        {:usage_observed,
         Keyword.put(ArchiveProjection.attributes(observation), :source_policy, policy)}
      end)

    [{:decisions_evaluation, evaluation}] ++ questions ++ attempts ++ usage
  end
end
