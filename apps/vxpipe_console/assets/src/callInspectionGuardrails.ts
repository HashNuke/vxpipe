import type { GuardrailAttempt, GuardrailEvaluation, GuardrailQuestionResult, RevisionedEntity } from "@vxpipe/core";
import { array, instant, invalid, literal, member, object, revision, string } from "./callInspectionFields";

const verdicts = ["passed", "blocked", "error", "cancelled", "skipped_empty", "not_applicable", "pending"] as const;
const events = ["before_turn", "after_turn", "before_outgoing_transfer"] as const;
const answers = ["yes", "no"] as const;

function strings(value: unknown, path: string) {
  return array(value, path).map((item, index) => string(item, `${path}[${index}]`));
}

function boolean(value: unknown, path: string) {
  return typeof value === "boolean" ? value : invalid(path);
}

function optionalFields(item: Record<string, unknown>, path: string) {
  return <T>(key: string, parse: (value: unknown, path: string) => T): T | undefined =>
    item[key] == null ? undefined : parse(item[key], `${path}.${key}`);
}

function questionResult(value: unknown, path: string): GuardrailQuestionResult {
  const row = object(value, path);
  const optional = optionalFields(row, path);
  const threshold = revision(row.threshold_hundredths, `${path}.threshold_hundredths`);
  if (threshold > 100) invalid(`${path}.threshold_hundredths`);
  const probability = row.probability_yes;
  if (probability != null && (typeof probability !== "number" || !Number.isFinite(probability) ||
      probability < 0 || probability > 1)) invalid(`${path}.probability_yes`);
  return {
    id: string(row.id, `${path}.id`),
    ordinal: revision(row.ordinal, `${path}.ordinal`),
    outcome: member(row.outcome, ["passed", "failed", "unavailable"], `${path}.outcome`),
    requiredAnswer: member(row.required_answer, answers, `${path}.required_answer`),
    question: optional("question", string),
    thresholdHundredths: threshold,
    probabilityYes: probability ?? undefined,
    inferredAnswer: optional("inferred_answer", (v, p) => member(v, answers, p)),
    feedback: optional("feedback", string),
    feedbackOrigin: optional("feedback_origin", (v, p) => member(v, ["configured", "authored", "fallback"], p)),
    feedbackDispatched: optional("feedback_dispatched", boolean),
  };
}

function attempt(value: unknown, path: string): GuardrailAttempt {
  const row = object(value, path);
  const optional = optionalFields(row, path);
  return {
    id: string(row.id, `${path}.id`),
    ordinal: revision(row.ordinal, `${path}.ordinal`),
    outcome: member(row.outcome, ["succeeded", "failed", "cancelled", "pending"], `${path}.outcome`),
    provider: optional("provider", string),
    model: optional("model", string),
    requestId: optional("request_id", string),
    errorCode: optional("error_code", string),
    retryOf: optional("retry_of", string),
    startedAt: optional("started_at", instant),
    endedAt: optional("ended_at", instant),
    durationMs: optional("duration_ms", revision),
    costs: optional("costs", (value, field) => array(value, field).map((entry, i) => {
      const costPath = field + "[" + i + "]";
      const cost = object(entry, costPath);
      return { currency: string(cost.currency, costPath + ".currency"), amount: string(cost.amount, costPath + ".amount") };
    })),
    inputTokens: optional("input_tokens", revision),
    outputTokens: optional("output_tokens", revision),
    totalTokens: optional("total_tokens", revision),
  };
}

function proposedTools(value: unknown, path: string) {
  return array(value, path).map((tool, index) => {
    const itemPath = `${path}[${index}]`;
    const row = object(tool, itemPath);
    return {id: string(row.id, itemPath + ".id"), name: string(row.name, itemPath + ".name")};
  });
}

export function guardrailEntity(input: unknown, path: string): RevisionedEntity<GuardrailEvaluation> {
  const entity = object(input, path);
  const id = string(entity.id, path + ".id");
  const valuePath = path + ".value";
  const row = object(entity.value, valuePath);
  literal(row.id, id, valuePath + ".id");
  const optional = optionalFields(row, valuePath);
  const contentUnavailable = optional("content_unavailable", (v, p) => member(v, ["denied", "unknown"] as const, p));
  const value: GuardrailEvaluation = {
    id, contentUnavailable,
    occurredAt: instant(row.occurred_at, valuePath + ".occurred_at"),
    participantId: string(row.participant_id, valuePath + ".participant_id"),
    event: member(row.event, events, valuePath + ".event"),
    outcome: member(row.outcome, verdicts, valuePath + ".outcome"),
    activationId: optional("activation_id", string),
    sourceParticipantId: optional("source_participant_id", string),
    sourceTurnId: optional("source_turn_id", string),
    responseTurnId: optional("response_turn_id", string),
    commandId: optional("command_id", string),
    candidateAttemptId: optional("candidate_attempt_id", string),
    transferInvocationId: optional("transfer_invocation_id", string),
    deliveredFactId: optional("delivered_fact_id", string),
    messageId: optional("message_id", string),
    destinationParticipantId: optional("destination_participant_id", string),
    transferOutcome: optional("transfer_outcome", (v, p) => member(v, ["completed", "failed"], p)),
    selectedProvider: optional("selected_provider", string), selectedModel: optional("selected_model", string),
    actualProvider: optional("actual_provider", string), actualModel: optional("actual_model", string),
    actualRequestId: optional("actual_request_id", string),
    startedAt: optional("started_at", instant), endedAt: optional("ended_at", instant),
    durationMs: optional("duration_ms", revision),
    errorCode: optional("error_code", string),
    policyRevision: optional("policy_revision", revision), policyDigest: optional("policy_digest", string),
    attemptIds: optional("attempt_ids", strings),
    attempts: array(row.attempts, valuePath + ".attempts").map((a, i) => attempt(a, `${valuePath}.attempts[${i}]`)),
    questions: contentUnavailable ? [] : array(row.questions, valuePath + ".questions")
      .map((q, i) => questionResult(q, `${valuePath}.questions[${i}]`)),
    ...(!contentUnavailable && {
      checkedText: optional("checked_text", string),
      proposedTools: optional("proposed_tools", proposedTools),
      questionIds: optional("question_ids", strings),
    }),
  };
  return {id, revision: revision(entity.revision, path + ".revision"), value};
}
