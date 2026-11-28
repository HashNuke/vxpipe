import type { GuardrailAttempt, GuardrailEvaluation } from "@vxpipe/core";
import { useEffect, useRef } from "react";
import { attemptsFor, decisionEvents, decisionTotals, failedQuestions, questionsFor, type DecisionsGroup } from "./decisionsMetrics.js";

const format = (value: number) => value.toLocaleString();
const count = (n: number, singular: string, plural = singular + "s") => `${format(n)} ${n === 1 ? singular : plural}`;
const readable = (value: string) => value[0]!.toUpperCase() + value.slice(1).replaceAll("_", " ");
const duration = (ms: number | undefined) => ms === undefined ? "unavailable" : format(ms) + " ms";

function Attempt({ attempt }: { attempt: GuardrailAttempt }) {
  const { inputTokens, outputTokens, totalTokens } = attempt;
  const tokens = (amount: number | undefined) => amount === undefined ? "unavailable" : format(amount);
  return <li><strong>Attempt {attempt.ordinal + 1}</strong>{attempt.retryOf || attempt.ordinal > 0 ? " · Retry" : ""}
    {" · "}{readable(attempt.outcome)}{attempt.errorCode && ` · ${readable(attempt.errorCode)}`}
    {" · API duration "}{duration(attempt.durationMs)}
    <p>{inputTokens === undefined && outputTokens === undefined && totalTokens === undefined ? "Token usage unavailable" :
      `Input ${tokens(inputTokens)} · Output ${tokens(outputTokens)} · Total ${tokens(totalTokens)} tokens`}</p>
    <p>Reported model {attempt.model ?? "unavailable"}{attempt.provider && ` · ${attempt.provider}`}</p>
    {attempt.costs?.length ? attempt.costs.map(cost => <p key={cost.currency}>Cost {cost.currency} {cost.amount}</p>) : <p>Cost unavailable</p>}
    {attempt.requestId && <p>Request {attempt.requestId}</p>}
  </li>;
}

function Check({ check, onShowGuardrail }: { check: GuardrailEvaluation; onShowGuardrail?: (id: string) => void }) {
  const questions = questionsFor(check);
  const attempts = attemptsFor(check);
  const failed = failedQuestions(check);
  const hasTurn = !!(check.sourceTurnId || check.responseTurnId);
  const model = [check.actualProvider, check.actualModel].filter(Boolean).join(" · ");
  return <details className="vx-decisions-check" data-outcome={check.outcome}>
    <summary><strong>{decisionEvents[check.event]}</strong> · {readable(check.outcome)}
      {check.outcome === "blocked" && failed !== undefined && ` · ${failed} of ${questions.length} questions failed`}
      {" · Gate "}{duration(check.durationMs)}</summary>
    <div className="vx-decisions-evidence">
      {check.sourceTurnId && <p>Source turn {check.sourceTurnId}</p>}
      {check.responseTurnId && <p>Response turn {check.responseTurnId}</p>}
      {check.candidateAttemptId && <p>Candidate {check.candidateAttemptId}</p>}
      {check.transferInvocationId && <p>Transfer {check.transferInvocationId}{check.destinationParticipantId && " · To " + check.destinationParticipantId}{check.transferOutcome && " · " + readable(check.transferOutcome)}</p>}
      {!hasTurn && !check.transferInvocationId && <p>Turn unavailable</p>}
      {check.errorCode && <p>{readable(check.errorCode)}</p>}
      {check.checkedText && !check.contentUnavailable && <p>{check.event === "before_turn" ? "Checked input" : check.outcome === "blocked" ? "Withheld draft" : "Checked candidate"} · {check.checkedText}</p>}
      {model && <p>Reported by {model}</p>}
      {onShowGuardrail && <button type="button" className="vx-decisions-link" onClick={() => onShowGuardrail(check.id)}>
        {hasTurn ? "Show evaluation in conversation" : "Show evaluation in private activity"}</button>}
      {check.contentUnavailable || (check.questionIds?.length ?? 0) > questions.length || !questions.length ?
        <p>Question details unavailable{check.contentUnavailable === "denied" && " under the call’s history permissions"}.</p> : null}
      {questions.length > 0 && <ol className="vx-decisions-list">{questions.map(q =>
        <li key={q.id}><strong>{q.question ?? "Question unavailable"}</strong>
          <p>{readable(q.outcome)} · Required {readable(q.requiredAnswer)} · Answer {q.inferredAnswer ? readable(q.inferredAnswer) : "unavailable"}</p>
          <p>P(Yes) {q.probabilityYes ?? "unavailable"} · Threshold {(q.thresholdHundredths / 100).toFixed(2)}</p>
          {q.feedback && <p>{q.feedbackOrigin === "fallback" ? "Fallback feedback" : "Configured feedback"} · {q.feedback}</p>}
          {q.feedbackDispatched && <p>Feedback sent to model</p>}
        </li>)}</ol>}
      <h4>API attempts</h4>
      {attempts.length > 0 && <ol className="vx-decisions-list">{attempts.map(attempt => <Attempt key={attempt.id} attempt={attempt} />)}</ol>}
      {check.attemptIds?.some(id => !attempts.some(attempt => attempt.id === id)) ?
        <p>Some submitted requests have no attempt detail.</p> : attempts.length === 0 && <p>No recorded API attempts.</p>}
    </div>
  </details>;
}

function TurnChecks({ checks, onShowGuardrail }: { checks: GuardrailEvaluation[]; onShowGuardrail?: (id: string) => void }) {
  const byOwner = new Map<string, GuardrailEvaluation[]>();
  for (const check of checks) {
    const turn = check.responseTurnId ?? check.sourceTurnId;
    const owner = turn ? "Turn " + turn : check.transferInvocationId ? "Transfer " + check.transferInvocationId : "Unassigned checks";
    const entries = byOwner.get(owner) ?? [];
    entries.push(check);
    byOwner.set(owner, entries);
  }
  return [...byOwner].map(([owner, entries]) => {
    const totals = decisionTotals(entries);
    return <section className="vx-decisions-owner" key={owner} aria-label={owner}>
      <h4>{owner}</h4>
      <p>{count(totals.evaluations, "evaluation")} · {count(totals.requests, "API request")}</p>
      {entries.map(check => <Check key={check.id} check={check} onShowGuardrail={onShowGuardrail} />)}
    </section>;
  });
}

function Timing({ label, values }: { label: string; values: number[] }) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  const median = sorted.length % 2 ? sorted[mid]! : (sorted[mid - 1]! + sorted[mid]!) / 2;
  return <p>{label} · Median {duration(median)} · p95 {duration(sorted[Math.ceil(sorted.length * 0.95) - 1]!)} · {count(sorted.length, "measurement")}</p>;
}

export function DecisionsDetails({ checks, group, participantName, id, onShowGuardrail, unlinkedRequests, rewrites }: {
  checks: GuardrailEvaluation[]; unlinkedRequests: number; rewrites: number; group?: DecisionsGroup; participantName?: string; id: string; onShowGuardrail?: (id: string) => void;
}) {
  const target = useRef<HTMLElement>(null);
  useEffect(() => { if (group) target.current?.focus(); }, [group?.key]);
  const totals = decisionTotals(checks);
  return <section className="vx-decisions-details" aria-label="Decisions detail" id={id}>
    <h2>Decisions</h2>
    <div className="vx-decisions-totals">
      <span>{count(totals.evaluations, "evaluation")}</span><span>{totals.blocked} blocked</span>
      {totals.errors > 0 && <span>{count(totals.errors, "checker error")}</span>}
      {totals.cancelled > 0 && <span>{count(totals.cancelled, "cancellation")}</span>}
      <span>{totals.failed === undefined ? "Question counts unavailable" : count(totals.failed, "failed question")}</span>
      <span>{count(totals.requests + unlinkedRequests, "API request")}</span>
      {totals.retries === undefined || unlinkedRequests > 0 ? <span>Retry count unavailable</span> : totals.retries > 0 && <span>{count(totals.retries, "transport retry", "transport retries")}</span>}
      {rewrites > 0 && <span>{count(rewrites, "LLM rewrite")}</span>}
    </div>
    {group && <section ref={target} tabIndex={-1} aria-label={participantName + " · " + group.model}>
      <h3>{participantName} · {group.model}</h3>
      <div className="vx-decisions-counts">{Object.entries(decisionEvents).map(([key, label]) => {
        const matches = group.checks.filter(check => check.event === key);
        if (!matches.length) return null;
        const outcomes = new Map<string, number>();
        for (const check of matches) outcomes.set(check.outcome, (outcomes.get(check.outcome) ?? 0) + 1);
        return <p key={key}>{label} · {[...outcomes].map(([outcome, n]) => n + " " + outcome.replaceAll("_", " ")).join(" · ")}</p>;
      })}
      <Timing label="Gate latency" values={group.checks.flatMap(c => c.durationMs === undefined ? [] : [c.durationMs])} />
      <Timing label="API latency" values={group.checks.flatMap(c => attemptsFor(c).flatMap(a => a.durationMs === undefined ? [] : [a.durationMs]))} />
      </div>
      <TurnChecks checks={group.checks} onShowGuardrail={onShowGuardrail} />
    </section>}
  </section>;
}
