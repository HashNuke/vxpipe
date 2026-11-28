import type { GuardrailAttempt, GuardrailEvaluation, Message, Metric, MetricObservation } from "@vxpipe/core";

export const decisionEvents = {
  before_turn: "Before turn", after_turn: "After turn", before_outgoing_transfer: "Before outgoing transfer",
};

export interface DecisionsGroup {
  key: string;
  participantId: string;
  model: string;
  checks: GuardrailEvaluation[];
  metrics: Map<string, Metric[]>;
}

function distinct<T extends { id: string }>(items: readonly T[]) {
  return [...new Map(items.map(item => [item.id, item])).values()];
}

export function questionsFor(check: GuardrailEvaluation) {
  return check.contentUnavailable ? [] : distinct(check.questions).sort((a, b) => a.ordinal - b.ordinal);
}

export function attemptsFor(check: GuardrailEvaluation) {
  return distinct(check.attempts).sort((a, b) => a.ordinal - b.ordinal);
}

function requestIds(check: GuardrailEvaluation) {
  return [...new Set([...(check.attemptIds ?? []), ...check.attempts.map(attempt => attempt.id)])];
}

function attemptOwner(id: string, participant: string, activation?: string, turn?: string, invocation?: string) {
  return JSON.stringify([id, participant, activation, turn, invocation]);
}

function evaluationTurn(check: GuardrailEvaluation) {
  if (check.event === "before_turn") return check.sourceTurnId;
  if (check.event === "after_turn") return check.responseTurnId;
  return check.responseTurnId ?? check.sourceTurnId;
}

function evaluationAttemptOwner(check: GuardrailEvaluation, id: string) {
  const invocation = check.event === "before_outgoing_transfer" ? check.transferInvocationId : undefined;
  return attemptOwner(id, check.participantId, check.activationId, evaluationTurn(check), invocation);
}

function metricOwner(metric: Metric) {
  if (metric.attemptId && metric.scope.kind === "participant-capability" && metric.scope.capability === "Decisions") {
    return attemptOwner(metric.attemptId, metric.scope.participantId, metric.activationId, metric.turnId, metric.toolCallId);
  }
}

/** Attach settled amounts only to dialogue explicitly identified by an authorized evaluation. */
export function messageDecisionMetrics(messages: Message[], checks: readonly GuardrailEvaluation[], observations: readonly MetricObservation[]) {
  const byId = new Map(messages.map(message => [message.id, message]));
  const owners = new Map<string, string | null>();
  for (const check of checks) {
    const message = check.messageId && byId.get(check.messageId);
    const participant = check.event === "before_turn" ? check.sourceParticipantId : check.participantId;
    const turn = evaluationTurn(check);
    const id = message && !check.contentUnavailable && check.activationId && turn &&
      message.participantId === participant && message.turnId === turn ? message.id : null;
    for (const attempt of requestIds(check)) {
      const key = evaluationAttemptOwner(check, attempt);
      owners.set(key, owners.has(key) && owners.get(key) !== id ? null : id);
    }
  }
  const linked = new Map<string, Metric[]>();
  for (const observation of distinct(observations)) {
    const owner = metricOwner(observation.value);
    const id = owner && owners.get(owner);
    if (!id) continue;
    const amounts = linked.get(id) ?? [];
    amounts.push(observation.value);
    linked.set(id, amounts);
  }
  return messages.map(message => {
    const measured = linked.get(message.id);
    return measured ? {...message, metrics: [...(message.metrics ?? []), ...measured]} : message;
  });
}

export function failedQuestions(check: GuardrailEvaluation) {
  if (check.outcome !== "blocked") return 0;
  const questions = questionsFor(check);
  if (check.contentUnavailable || !questions.length || check.questionIds?.some(id => !questions.some(q => q.id === id))
    || questions.some(q => q.outcome === "unavailable")) return undefined;
  return questions.filter(q => q.outcome === "failed").length;
}

function physicalAttempts(checks: readonly GuardrailEvaluation[]) {
  const physical = new Map<string, GuardrailAttempt | undefined>();
  for (const check of checks) {
    for (const id of check.attemptIds ?? []) {
      const key = evaluationAttemptOwner(check, id);
      if (!physical.has(key)) physical.set(key, undefined);
    }
    for (const attempt of check.attempts) physical.set(evaluationAttemptOwner(check, attempt.id), attempt);
  }
  return physical;
}

export function decisionTotals(checks: readonly GuardrailEvaluation[]) {
  const attempts = [...physicalAttempts(checks).values()];
  const failed = checks.map(failedQuestions);
  return {
    evaluations: checks.length,
    blocked: checks.filter(check => check.outcome === "blocked").length,
    errors: checks.filter(check => check.outcome === "error").length,
    cancelled: checks.filter(check => check.outcome === "cancelled").length,
    failed: failed.every(count => count !== undefined) ? failed.reduce((sum, count) => sum + count, 0) : undefined,
    requests: attempts.length,
    retries: attempts.every(a => a !== undefined) ? attempts.filter(a => a.retryOf || a.ordinal > 0).length : undefined,
  };
}

function groupMetrics(group: DecisionsGroup, additional: Metric[]) {
  const { evaluations, requests } = decisionTotals(group.checks);
  const scope = { kind: "participant-capability", participantId: group.participantId, capability: "Decisions" } as const;
  const summary = (label: string, value: number | null, unit: string, description: string) =>
    group.metrics.set(label, [{ label, value, unit, description, source: group.model, scope }]);

  summary("Evaluations", evaluations, "checks", "Distinct guardrail evaluations for this participant and model.");
  summary("API requests", requests, "requests", "Distinct submitted Decisions API attempts, including retries.");
  const attempts = physicalAttempts(group.checks);
  for (const [key, label] of [["inputTokens", "Input tokens"], ["outputTokens", "Output tokens"], ["totalTokens", "Total tokens"]] as const) {
    const reported = new Map<string, number>();
    for (const [owner, attempt] of attempts) {
      if (attempt?.[key] !== undefined) reported.set(owner, attempt[key]);
    }
    for (const metric of additional) {
      const owner = metricOwner(metric);
      if (metric.label === label && owner && metric.value !== null && !attempts.get(owner)) {
        reported.set(owner, metric.value);
      }
    }
    const amounts = [...reported.values()];
    if (amounts.length) summary(label, amounts.length === requests ? amounts.reduce((a, b) => a + b, 0) : null,
      "tokens", `Provider-reported ${label.toLowerCase()} available for ${amounts.length} of ${requests} requests.`);
  }
  for (const metric of additional) {
    if (["Requests", "API requests", "Input tokens", "Output tokens", "Total tokens"].includes(metric.label)) continue;
    const values = group.metrics.get(metric.label) ?? [];
    values.push(metric);
    group.metrics.set(metric.label, values);
  }
}

/** Keep unmatched settlement rows visible when the archive has no corresponding evaluation. */
export function groupDecisions(evaluations: readonly GuardrailEvaluation[], metrics: readonly Metric[]) {
  const checks = distinct(evaluations).sort((a, b) => a.occurredAt.localeCompare(b.occurredAt));
  const groups = new Map<string, DecisionsGroup>();
  const byAttempt = new Map<string, DecisionsGroup>();
  for (const check of checks) {
    const provider = check.selectedProvider ?? check.actualProvider;
    const modelName = check.selectedModel ?? check.actualModel;
    const model = [provider, modelName].filter(Boolean).join(" · ") || "Model unavailable";
    const key = JSON.stringify([check.participantId, provider, modelName]);
    const group: DecisionsGroup = groups.get(key) ?? { key, model, participantId: check.participantId, checks: [], metrics: new Map() };
    group.checks.push(check);
    groups.set(key, group);
    for (const id of requestIds(check)) {
      byAttempt.set(evaluationAttemptOwner(check, id), group);
    }
  }
  const otherMetrics: Metric[] = [];
  const perGroup = new Map<DecisionsGroup, Metric[]>();
  const unlinkedRequests = new Set<string>();
  for (const metric of metrics) {
    const owner = metricOwner(metric);
    const group = owner && byAttempt.get(owner);
    if (!group || metric.scope.kind !== "participant-capability" || metric.scope.capability !== "Decisions" ||
      metric.scope.participantId !== group.participantId) {
      otherMetrics.push(metric);
      if (metric.attemptId && (!owner || !byAttempt.has(owner)) && "capability" in metric.scope &&
        metric.scope.capability === "Decisions" && metric.label === "Requests" && metric.value === 1) {
        unlinkedRequests.add(owner ?? JSON.stringify([metric.scope, metric.attemptId, metric.activationId, metric.turnId, metric.toolCallId]));
      }
      continue;
    }
    const amounts = perGroup.get(group) ?? [];
    amounts.push(metric);
    perGroup.set(group, amounts);
  }
  for (const group of groups.values()) groupMetrics(group, perGroup.get(group) ?? []);
  // The presenter emits one LLM rewrite measurement per confirmed model dispatch.
  const rewrites = otherMetrics.reduce((total, metric) =>
    metric.label === "Rewrites" && "capability" in metric.scope && metric.scope.capability === "LLM"
      ? total + (metric.value ?? 0) : total, 0);
  return { checks, groups: [...groups.values()], otherMetrics, unlinkedRequests: unlinkedRequests.size, rewrites };
}
