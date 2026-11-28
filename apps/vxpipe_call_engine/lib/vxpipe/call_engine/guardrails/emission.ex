defmodule Vxpipe.CallEngine.Guardrails.Emission do
  @moduledoc """
  Pure builders for private Decisions (Guardrails) history facts and usage.

  The live producer is `Vxpipe.CallEngine.Guardrails.Participant`. It captures
  one logical evaluation, all per-question results (including partial), and
  per-physical-attempt observed metadata, then hands a report map to the
  trusted emission callback wired by `PlanStartup.Guardrails`.

  `RoomAuthority.DecisionsPublication` validates the report against the owning
  activation, resolves the allowed source interval, and emits bounded private
  facts through the existing archive lifecycle. Content-saving policy lives at
  the authoritative source; unknown intervals default to safe redaction.

  Probabilities, question text, feedback and draft text never enter the usage
  ledger. Unknown provider tokens stay unknown; only actually submitted
  attempts produce `requests` usage. `feedback_dispatched` is true only when a
  semantic block was actually handed to the model repair path, never invented.
  """

  alias Vxpipe.CallEngine.Id

  alias Vxpipe.CallEngine.Usage.{
    Attribution,
    Decisions,
    Measurement,
    Observation,
    ProviderContext
  }

  @events [:before_turn, :after_turn, :before_outgoing_transfer]
  @evaluation_outcomes [:passed, :blocked, :error, :cancelled, :skipped_empty, :not_applicable]
  @question_outcomes [:passed, :failed, :unavailable]
  @attempt_outcomes [:succeeded, :failed, :cancelled]
  @error_codes [
    :cancelled,
    :timeout,
    :unavailable,
    :unauthorized,
    :transport_error,
    :rate_limited,
    :invalid_result,
    :refused,
    :oversized,
    :retry_exhausted,
    :stale
  ]

  @max_questions 32
  @max_attempts 8

  @doc "Builds a terminal emission report map. Returns {:ok, report} or {:error, reason}."
  @spec build_report(map()) :: {:ok, map()} | {:error, term()}
  def build_report(attrs) when is_map(attrs) do
    with {:ok, event} <- fetch_event(attrs),
         {:ok, outcome} <- fetch_outcome(attrs),
         :ok <- validate_error_code(Map.get(attrs, :error_code)),
         {:ok, evaluation_id} <- fetch_id(attrs, :evaluation_id),
         {:ok, questions} <- fetch_questions(attrs),
         {:ok, outcomes} <- fetch_outcomes(attrs, questions),
         {:ok, attempts} <- fetch_attempts(attrs),
         {:ok, policy_revision} <- fetch_revision(attrs),
         {:ok, policy_digest} <- fetch_digest(attrs),
         :ok <- validate_counts(questions, attempts) do
      started_at = Map.get(attrs, :started_at, DateTime.utc_now(:millisecond))
      ended_at = Map.get(attrs, :ended_at, started_at)

      duration_ms =
        case Map.get(attrs, :duration_ms) do
          measured when is_integer(measured) and measured >= 0 -> measured
          _ -> max(DateTime.diff(ended_at, started_at, :millisecond), 0)
        end

      report = %{
        evaluation_id: evaluation_id,
        event: event,
        outcome: outcome,
        error_code: Map.get(attrs, :error_code),
        participant_id: Map.get(attrs, :participant_id),
        activation_id: Map.get(attrs, :activation_id),
        source_participant_id: Map.get(attrs, :source_participant_id),
        source_policy_revision: Map.get(attrs, :source_policy_revision),
        source_turn_id: Map.get(attrs, :source_turn_id),
        response_turn_id: Map.get(attrs, :response_turn_id),
        transfer_invocation_id: Map.get(attrs, :transfer_invocation_id),
        command_id: Map.get(attrs, :command_id),
        candidate_attempt_id: Map.get(attrs, :candidate_attempt_id),
        policy_revision: policy_revision,
        policy_digest: policy_digest,
        selected_provider: Map.get(attrs, :selected_provider),
        selected_model: Map.get(attrs, :selected_model),
        actual_provider: Map.get(attrs, :actual_provider),
        actual_model: Map.get(attrs, :actual_model),
        actual_request_id: Map.get(attrs, :actual_request_id),
        question_ids: Enum.map(questions, & &1.id),
        questions: questions,
        outcomes: outcomes,
        feedback: Map.get(attrs, :feedback, []),
        feedback_dispatched: Map.get(attrs, :feedback_dispatched, false) == true,
        attempts: attempts,
        usage_observations: Map.get(attrs, :usage_observations, []),
        started_at: started_at,
        ended_at: ended_at,
        duration_ms: duration_ms,
        content_unavailable: Map.get(attrs, :content_unavailable),
        tenant_id: Map.get(attrs, :tenant_id),
        call_id: Map.get(attrs, :call_id),
        room_id: Map.get(attrs, :room_id),
        incarnation_id: Map.get(attrs, :incarnation_id),
        late: Map.get(attrs, :late, false) == true
      }

      {:ok, report}
    else
      _invalid -> {:error, :invalid_decisions_report}
    end
  end

  def build_report(_attrs), do: {:error, :invalid_decisions_report}

  @doc "Builds evaluation fact attributes for Recorder.internal_fact/3."
  @spec evaluation_fact(map(), map()) :: {:ok, keyword()} | {:error, term()}
  def evaluation_fact(%{} = report, %{} = envelope) do
    with {:ok, report} <- build_report(report) do
      payload =
        %{
          "evaluation_id" => report.evaluation_id,
          "event" => Atom.to_string(report.event),
          "outcome" => Atom.to_string(report.outcome),
          "error_code" => error_string(report.error_code),
          "policy_revision" => report.policy_revision,
          "policy_digest" => report.policy_digest,
          "source_turn_id" => report.source_turn_id,
          "response_turn_id" => report.response_turn_id,
          "candidate_attempt_id" => report.candidate_attempt_id,
          "selected_provider" => report.selected_provider,
          "selected_model" => report.selected_model,
          "actual_provider" => report.actual_provider,
          "actual_model" => report.actual_model,
          "actual_request_id" => report.actual_request_id,
          "question_ids" => report.question_ids,
          "attempt_ids" => Enum.map(report.attempts, & &1.attempt_id),
          "started_at" => DateTime.to_iso8601(report.started_at),
          "ended_at" => DateTime.to_iso8601(report.ended_at),
          "duration_ms" => report.duration_ms,
          "content_unavailable" => report.content_unavailable
        }
        |> maybe_put_transfer(report)

      {:ok,
       [
         id: report.evaluation_id,
         participant_id: report.participant_id,
         activation_id: report.activation_id,
         source_participant_id: report.source_participant_id,
         command_id: report.command_id,
         correlation_id: correlation_id(report),
         tool_call_id: tool_call_id(report),
         occurred_at: Map.get(envelope, :occurred_at, report.ended_at),
         source_policy: Map.get(envelope, :source_policy, %{}),
         payload: payload
       ]}
    end
  end

  @doc "Builds one question fact per question in authored order."
  @spec question_facts(map(), map()) :: {:ok, [{atom(), keyword()}]} | {:error, term()}
  def question_facts(%{} = report, %{} = envelope) do
    with {:ok, report} <- build_report(report) do
      facts =
        report.questions
        |> Enum.with_index()
        |> Enum.map(fn {question, ordinal} ->
          outcome = Enum.find(report.outcomes, &(&1.question_id == question.id))

          {:decisions_question_result,
           question_attributes(report, question, outcome, ordinal, envelope)}
        end)

      {:ok, facts}
    end
  end

  @doc "Builds one attempt fact per physical attempt."
  @spec attempt_facts(map(), map()) :: {:ok, [{atom(), keyword()}]} | {:error, term()}
  def attempt_facts(%{} = report, %{} = envelope) do
    with {:ok, report} <- build_report(report) do
      facts =
        Enum.map(report.attempts, fn attempt ->
          {:decisions_attempt, attempt_attributes(report, attempt, envelope)}
        end)

      {:ok, facts}
    end
  end

  @doc """
  Builds `:decisions` usage observations, one `requests` row per submitted
  attempt plus provider-reported token rows. Unknown tokens stay unknown.
  """
  @spec usage_observations(map(), map()) :: {:ok, [Observation.t()]} | {:error, term()}
  def usage_observations(%{} = report, %{} = identity) do
    with {:ok, report} <- build_report(report),
         {:ok, tenant_id} <- Map.fetch(identity, :tenant_id),
         {:ok, call_id} <- Map.fetch(identity, :call_id) do
      observations =
        Enum.flat_map(report.attempts, fn attempt ->
          attempt_observations(report, attempt, tenant_id, call_id, identity)
        end)

      {:ok, observations}
    else
      _ -> {:error, :invalid_decisions_usage}
    end
  end

  @doc """
  Builds late billable usage for a cancelled evaluation without reopening the
  gate. Uses the same stable delivery IDs with an incremented source sequence
  so settlement supersedes instead of duplicating.
  """
  @spec late_usage(map(), map()) :: {:ok, [Observation.t()]} | {:error, term()}
  def late_usage(%{} = report, usage) when is_map(usage) do
    case report.attempts do
      [attempt] -> {:ok, late_observations(report, attempt, usage)}
      _ -> {:error, :unknown_attempt}
    end
  end

  # --- internals ---

  defp question_attributes(report, question, outcome, ordinal, envelope) do
    outcome_map = outcome || %{probability_yes: nil, inferred_answer: nil, outcome: :unavailable}
    failed? = outcome_map.outcome == :failed
    {feedback, origin} = question_feedback(question, outcome_map, report)

    payload = %{
      "evaluation_id" => report.evaluation_id,
      "question_id" => question.id,
      "ordinal" => ordinal,
      "policy_revision" => report.policy_revision,
      "policy_digest" => report.policy_digest,
      "required_answer" => required_string(question.required_answer),
      "threshold_hundredths" => question.threshold_hundredths,
      "probability_yes" => outcome_map.probability_yes,
      "inferred_answer" => inferred_string(outcome_map.inferred_answer),
      "outcome" => Atom.to_string(outcome_map.outcome),
      "question" => question_text(question),
      "response" => question_response(question),
      "feedback" => if(failed?, do: feedback, else: nil),
      "feedback_origin" => if(failed?, do: origin, else: nil),
      "feedback_dispatched" => false,
      "content_unavailable" => report.content_unavailable
    }

    [
      id: report.evaluation_id <> ":" <> question.id,
      participant_id: report.participant_id,
      activation_id: report.activation_id,
      source_participant_id: report.source_participant_id,
      command_id: report.command_id,
      correlation_id: correlation_id(report),
      tool_call_id: tool_call_id(report),
      occurred_at: Map.get(envelope, :occurred_at, report.ended_at),
      source_policy: Map.get(envelope, :source_policy, %{}),
      payload: payload
    ]
  end

  defp attempt_attributes(report, attempt, envelope) do
    payload = %{
      "evaluation_id" => report.evaluation_id,
      "attempt_id" => attempt.attempt_id,
      "ordinal" => attempt.ordinal,
      "event" => Atom.to_string(report.event),
      "outcome" => Atom.to_string(attempt.outcome),
      "error_code" => error_string(attempt.error_code),
      "policy_revision" => report.policy_revision,
      "policy_digest" => report.policy_digest,
      "provider" => Map.get(attempt, :provider),
      "model" => Map.get(attempt, :model),
      "request_id" => Map.get(attempt, :request_id),
      "retry_of" => Map.get(attempt, :retry_of),
      "started_at" => DateTime.to_iso8601(attempt.started_at),
      "ended_at" => if(attempt.ended_at, do: DateTime.to_iso8601(attempt.ended_at)),
      "duration_ms" => Map.get(attempt, :duration_ms),
      "content_unavailable" => report.content_unavailable
    }

    [
      id: attempt.attempt_id,
      participant_id: report.participant_id,
      activation_id: report.activation_id,
      source_participant_id: report.source_participant_id,
      command_id: report.command_id,
      correlation_id: correlation_id(report),
      tool_call_id: tool_call_id(report),
      occurred_at: Map.get(envelope, :occurred_at, attempt.ended_at),
      source_policy: Map.get(envelope, :source_policy, %{}),
      payload: payload
    ]
  end

  defp attempt_observations(report, attempt, tenant_id, call_id, identity) do
    with {:ok, attribution} <- attempt_attribution(report, identity),
         {:ok, provider} <- attempt_provider(report, attempt),
         {:ok, requests} <-
           Measurement.new(
             component: "requests",
             unit: :requests,
             quantity: 1,
             mode: :delta,
             status: :final,
             provenance: :locally_measured
           ),
         {:ok, requests_observation} <-
           Observation.new(
             id: observation_id(attempt.attempt_id, "requests"),
             delivery_id: delivery_id(attempt.attempt_id, "requests"),
             source_sequence: attempt.ordinal,
             tenant_id: tenant_id,
             call_id: call_id,
             attempt_id: attempt.attempt_id,
             capability: :decisions,
             provider: provider,
             attribution: attribution,
             measurement: requests,
             outcome: usage_outcome(attempt.outcome),
             observed_at: attempt.ended_at
           ) do
      [
        requests_observation
        | token_observations(attempt, tenant_id, call_id, provider, attribution, :final)
      ]
    else
      _invalid -> []
    end
  end

  defp token_observations(attempt, tenant_id, call_id, provider, attribution, status) do
    correction? = status == :correction

    for {component, quantity, parent} <- Decisions.token_components(attempt.usage),
        {:ok, measurement} <- [
          Measurement.new(
            component: component,
            unit: :tokens,
            quantity: quantity,
            mode: :cumulative,
            status: status,
            provenance: :provider_reported,
            included_in: parent
          )
        ],
        {:ok, observation} <- [
          Observation.new(
            id: observation_id(attempt.attempt_id, component),
            delivery_id: delivery_id(attempt.attempt_id, component),
            source_sequence: if(correction?, do: attempt.ordinal + 1, else: attempt.ordinal),
            tenant_id: tenant_id,
            call_id: call_id,
            attempt_id: attempt.attempt_id,
            capability: :decisions,
            provider: provider,
            attribution: attribution,
            measurement: measurement,
            outcome: usage_outcome(attempt.outcome),
            observed_at:
              if(correction?, do: DateTime.utc_now(:millisecond), else: attempt.ended_at)
          )
        ],
        do: observation
  end

  @doc false
  def late_observations(report, attempt, usage) do
    with {:ok, attribution} <- attempt_attribution(report, report),
         {:ok, provider} <- attempt_provider(report, attempt) do
      token_observations(
        Map.put(attempt, :usage, usage),
        report.tenant_id,
        report.call_id,
        provider,
        attribution,
        :correction
      )
    else
      _ -> []
    end
  end

  defp attempt_attribution(report, identity) do
    Attribution.new(
      room_id: Map.get(identity, :room_id),
      incarnation_id: Map.get(identity, :incarnation_id),
      participant_id: report.participant_id,
      activation_id: report.activation_id,
      turn_id: turn_id(report),
      tool_call_id: tool_call_id(report)
    )
  end

  defp attempt_provider(report, attempt) do
    provider_name = attempt.provider || report.selected_provider || report.actual_provider

    if is_binary(provider_name) and provider_name != "" do
      ProviderContext.new(
        name: provider_name,
        integration_id: nil,
        model: attempt.model,
        request_id: attempt.request_id
      )
    else
      {:error, :invalid_decisions_usage}
    end
  end

  defp turn_id(%{event: :before_turn} = report), do: report.source_turn_id
  defp turn_id(%{event: :after_turn} = report), do: report.response_turn_id
  defp turn_id(_report), do: nil

  defp correlation_id(%{event: :before_turn} = report), do: report.source_turn_id
  defp correlation_id(%{event: :after_turn} = report), do: report.response_turn_id

  defp correlation_id(%{event: :before_outgoing_transfer} = report),
    do: report.transfer_invocation_id

  defp correlation_id(_report), do: nil

  defp tool_call_id(%{event: :before_outgoing_transfer} = report),
    do: report.transfer_invocation_id

  defp tool_call_id(_report), do: nil

  defp question_feedback(question, %{outcome: :failed}, %{outcome: :blocked}) do
    response = Map.get(question, :response) || Map.get(question, "response")

    if is_binary(response) and String.trim(response) != "" do
      {response, "authored"}
    else
      text = Map.get(question, :question) || Map.get(question, "question") || ""
      required = Map.get(question, :required_answer) || Map.get(question, "required_answer")
      label = if required in [:yes, "yes"], do: "Yes", else: "No"
      {"Failed guardrail: #{text} Required: #{label}.", "fallback"}
    end
  end

  defp question_feedback(_question, _outcome, _report), do: {nil, nil}

  defp question_text(question) do
    case Map.get(question, :question) || Map.get(question, "question") do
      text when is_binary(text) and text != "" -> text
      _ -> nil
    end
  end

  defp question_response(question) do
    case Map.get(question, :response) || Map.get(question, "response") do
      text when is_binary(text) and text != "" -> text
      _ -> nil
    end
  end

  defp maybe_put_transfer(payload, %{event: :before_outgoing_transfer} = report) do
    case report.transfer_invocation_id do
      id when is_binary(id) and id != "" -> Map.put(payload, "transfer_invocation_id", id)
      _ -> payload
    end
  end

  defp maybe_put_transfer(payload, _report), do: payload

  defp usage_outcome(:succeeded), do: :succeeded
  defp usage_outcome(:failed), do: :failed
  defp usage_outcome(:cancelled), do: :cancelled
  defp usage_outcome(_), do: :unknown

  defp observation_id(attempt_id, component) do
    digest = :crypto.hash(:sha256, attempt_id <> ":" <> component)
    "uobs_" <> Base.url_encode64(digest, padding: false)
  end

  defp delivery_id(attempt_id, component), do: attempt_id <> ":" <> component

  @doc false
  def new_evaluation_id, do: Id.generate(:decisions_evaluation)

  @doc false
  def new_attempt_id, do: Id.generate(:decisions_attempt)

  defp fetch_event(%{event: event}) when event in @events, do: {:ok, event}
  defp fetch_event(_), do: :error

  defp fetch_outcome(%{outcome: outcome}) when outcome in @evaluation_outcomes, do: {:ok, outcome}
  defp fetch_outcome(_), do: :error

  defp validate_error_code(nil), do: :ok
  defp validate_error_code(code) when code in @error_codes, do: :ok
  defp validate_error_code(_), do: :error

  defp fetch_id(attrs, field) do
    case Map.fetch(attrs, field) do
      {:ok, value} when is_binary(value) and byte_size(value) in 1..128 -> {:ok, value}
      _ -> :error
    end
  end

  defp fetch_questions(%{questions: questions, outcomes: outcomes})
       when is_list(questions) and is_list(outcomes) do
    if length(questions) <= @max_questions and
         Enum.all?(questions, &valid_question?/1) do
      {:ok, questions}
    else
      :error
    end
  end

  defp fetch_questions(_), do: :error

  defp valid_question?(%{id: id, required_answer: required, threshold_hundredths: threshold})
       when is_binary(id) and required in [:yes, :no, "yes", "no"] and is_integer(threshold) and
              threshold >= 0 and threshold <= 100,
       do: true

  defp valid_question?(_), do: false

  defp fetch_outcomes(%{outcomes: outcomes}, questions) when is_list(outcomes) do
    ids = MapSet.new(Enum.map(questions, & &1.id))

    if Enum.all?(outcomes, &valid_outcome?(&1, ids)) do
      {:ok, outcomes}
    else
      :error
    end
  end

  defp fetch_outcomes(_, _), do: :error

  defp valid_outcome?(%{question_id: id, outcome: outcome} = detail, ids) do
    outcome in @question_outcomes and MapSet.member?(ids, id) and
      valid_score?(outcome, detail)
  end

  defp valid_outcome?(_, _), do: false

  defp valid_score?(:unavailable, %{probability_yes: nil, inferred_answer: nil}), do: true
  defp valid_score?(:unavailable, _), do: false

  defp valid_score?(_outcome, %{probability_yes: score, inferred_answer: inferred}) do
    is_number(score) and score >= 0 and score <= 1 and inferred in [:yes, :no, "yes", "no", nil]
  end

  defp valid_score?(_, _), do: false

  defp fetch_attempts(%{attempts: attempts}) when is_list(attempts) do
    if length(attempts) <= @max_attempts and Enum.all?(attempts, &valid_attempt?/1) do
      {:ok, attempts}
    else
      :error
    end
  end

  defp fetch_attempts(_), do: :error

  defp valid_attempt?(%{attempt_id: id, ordinal: ordinal, outcome: outcome} = attempt)
       when is_binary(id) and is_integer(ordinal) and ordinal >= 0 and
              outcome in @attempt_outcomes do
    validate_error_code(Map.get(attempt, :error_code)) == :ok and
      is_struct(Map.get(attempt, :started_at), DateTime) and
      is_struct(Map.get(attempt, :ended_at), DateTime) and
      is_integer(Map.get(attempt, :duration_ms, 0))
  end

  defp valid_attempt?(_), do: false

  defp fetch_revision(%{policy_revision: revision}) when is_integer(revision) and revision >= 0,
    do: {:ok, revision}

  defp fetch_revision(_), do: :error

  defp fetch_digest(%{policy_digest: "sha256:" <> _} = attrs), do: {:ok, attrs.policy_digest}
  defp fetch_digest(_), do: :error

  defp validate_counts(questions, attempts) do
    if length(questions) <= @max_questions and length(attempts) <= @max_attempts,
      do: :ok,
      else: :error
  end

  defp error_string(nil), do: nil
  defp error_string(code) when is_atom(code), do: Atom.to_string(code)
  defp error_string(code) when is_binary(code), do: code

  defp required_string(:yes), do: "yes"
  defp required_string(:no), do: "no"
  defp required_string("yes"), do: "yes"
  defp required_string("no"), do: "no"
  defp required_string(_), do: nil

  defp inferred_string(:yes), do: "yes"
  defp inferred_string(:no), do: "no"
  defp inferred_string("yes"), do: "yes"
  defp inferred_string("no"), do: "no"
  defp inferred_string(_), do: nil
end
