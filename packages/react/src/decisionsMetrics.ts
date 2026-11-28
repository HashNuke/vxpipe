import type { GuardrailEvaluation, Metric } from "@vxpipe/core";

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

export function failedQuestions(check: GuardrailEvaluation) {
  if (check.outcome !== "blocked") return 0;
  const questions = questionsFor(check);
  if (check.contentUnavailable || !questions.length || check.questionIds?.some(id => !questions.some(q => q.id === id))
    || questions.some(q => q.outcome === "unavailable")) return undefined;
  return questions.filter(q => q.outcome === "failed").length;
}

export function decisionTotals(checks: readonly GuardrailEvaluation[]) {
  const attempts = distinct(checks.flatMap(check => check.attempts));
  const ids = new Set(checks.flatMap(requestIds));
  const failed = checks.map(failedQuestions);
  return {
    evaluations: checks.length,
    blocked: checks.filter(check => check.outcome === "blocked").length,
    errors: checks.filter(check => check.outcome === "error").length,
    cancelled: checks.filter(check => check.outcome === "cancelled").length,
    failed: failed.every(count => count !== undefined) ? failed.reduce((sum, count) => sum + count, 0) : undefined,
    requests: ids.size,
    retries: ids.size === attempts.length ? attempts.filter(a => a.retryOf || a.ordinal > 0).length : undefined,
  };
}

function groupMetrics(group: DecisionsGroup, additional: Metric[]) {
  const { evaluations, requests } = decisionTotals(group.checks);
  const scope = { kind: "participant-capability", participantId: group.participantId, capability: "Decisions" } as const;
  const summary = (label: string, value: number | null, unit: string, description: string) =>
    group.metrics.set(label, [{ label, value, unit, description, source: group.model, scope }]);

  summary("Evaluations", evaluations, "checks", "Distinct guardrail evaluations for this participant and model.");
  summary("API requests", requests, "requests", "Distinct submitted Decisions API attempts, including retries.");
  const attempts = distinct(group.checks.flatMap(check => check.attempts));
  for (const [key, label] of [["inputTokens", "Input tokens"], ["outputTokens", "Output tokens"], ["totalTokens", "Total tokens"]] as const) {
    const reported = new Map(attempts.flatMap(attempt => attempt[key] === undefined ? [] : [[attempt.id, attempt[key]] as const]));
    for (const metric of additional) {
      if (metric.label === label && metric.attemptId && metric.value !== null && !attempts.some(a => a.id === metric.attemptId)) {
        reported.set(metric.attemptId, metric.value);
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
  const linkedAttempts = new Set<string>();
  const ownership = (id: string, participant: string, activation?: string, turn?: string) =>
    JSON.stringify([id, participant, activation, turn]);
  for (const check of checks) {
    const provider = check.selectedProvider ?? check.actualProvider;
    const modelName = check.selectedModel ?? check.actualModel;
    const model = [provider, modelName].filter(Boolean).join(" · ") || "Model unavailable";
    const key = JSON.stringify([check.participantId, provider, modelName]);
    const group: DecisionsGroup = groups.get(key) ?? { key, model, participantId: check.participantId, checks: [], metrics: new Map() };
    group.checks.push(check);
    groups.set(key, group);
    const turn = check.event === "before_turn" ? check.sourceTurnId :
      check.event === "after_turn" ? check.responseTurnId : check.responseTurnId ?? check.sourceTurnId;
    for (const id of requestIds(check)) {
      byAttempt.set(ownership(id, check.participantId, check.activationId, turn), group);
      linkedAttempts.add(id);
    }
  }
  const otherMetrics: Metric[] = [];
  const perGroup = new Map<DecisionsGroup, Metric[]>();
  const unlinkedRequests = new Set<string>();
  for (const metric of metrics) {
    const group = metric.attemptId && metric.scope.kind === "participant-capability" &&
      byAttempt.get(ownership(metric.attemptId, metric.scope.participantId, metric.activationId, metric.turnId));
    if (!group || metric.scope.kind !== "participant-capability" || metric.scope.capability !== "Decisions" ||
      metric.scope.participantId !== group.participantId) {
      otherMetrics.push(metric);
      if (metric.attemptId && !linkedAttempts.has(metric.attemptId) && "capability" in metric.scope &&
        metric.scope.capability === "Decisions" && metric.label === "Requests" && metric.value === 1) {
        unlinkedRequests.add(metric.attemptId);
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
