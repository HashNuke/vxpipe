import { useId, useLayoutEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { createCallDetailsStore, type CallDetailsTimelineEntity, type MetricObservation } from "@vxpipe/core";
import { CallDetailsPage } from "../CallDetailsPage";
import { callDetailsFixture } from "../callDetailsFixtures";
import { StoryCallBreadcrumbs } from "./StoryCallBreadcrumbs";
import { agents, inspectionFixture, type Agent, type GuardrailCheck, type GuardrailScenario } from "./guardrailInspectionFixtures";
import "./guardrailInspection.css";

function count(value: number, name: string, plural = name + "s") {
  return value + " " + (value === 1 ? name : plural);
}

function summarize(checks: GuardrailCheck[]) {
  const blocked = checks.filter(check => check.status === "Blocked");
  return {
    evaluations: checks.length, blocked: blocked.length, errors: checks.filter(check => check.status === "Error").length,
    failed: blocked.some(check => check.evidence === null) ? null :
      blocked.reduce((total, check) => total + (check.evidence?.questions.filter(q => q.outcome === "Failed").length ?? 0), 0),
    requests: checks.reduce((total, check) => total + check.attempts.length, 0),
    retries: checks.reduce((total, check) => total + Math.max(0, check.attempts.length - 1), 0),
    rewrites: checks.filter(check => check.rewrite).length,
  };
}

function CheckDetail({ check, model, inMetrics, showInChat }: {
  check: GuardrailCheck; model: string; inMetrics: boolean; showInChat: (id: string) => void;
}) {
  const { evidence } = check;
  const replacementId = evidence?.replacementEvaluationId;
  const { failed } = summarize([check]);
  return <details className="guardrail-check" data-status={check.status} id={"evaluation-" + check.id}>
    <summary>{agents[check.agent]} · <strong>{check.event}</strong> · {check.status}
      {check.status === "Blocked" && evidence && <> · <span>{failed} of {evidence.questions.length} questions failed</span></>}
      {" · "}<span>Gate {check.elapsed} ms</span></summary>
    <div className="guardrail-evidence">
      <p>Selected model · {model}</p>
      <p>{check.transfer ? "Transfer to " + check.transfer.destination + " · " + check.transfer.id : "Turn " + check.turn?.split("-")[1]}</p>
      {inMetrics && <button type="button" className="guardrail-inspect" onClick={() => showInChat(check.id)}>
        {check.turn ? "Show evaluation in conversation" : "Show evaluation in private activity"}
      </button>}
      {evidence === null ? <p>Question details unavailable under the call’s history permissions.</p> : <>
        <ol>{evidence.questions.map(q => <li key={q.id}>
          <strong>{q.question}</strong>
          <div>{q.outcome} · Required {q.required} · Answer {q.inferred ?? "unavailable"}</div>
          {q.probability === null ? <div>P(Yes) unavailable · Threshold {q.threshold.toFixed(2)}</div> :
            <div>P(Yes) <code>{q.probability} {q.inferred === "Yes" ? "≥" : "<"} {q.threshold.toFixed(2)}</code></div>}
          {q.feedback && <div className="guardrail-feedback">
            <small>{q.feedback.origin}</small><p>{q.feedback.line}</p>
          </div>}
        </li>)}</ol>
        {evidence.rejectedDraft && <p>Withheld draft · {evidence.rejectedDraft}</p>}
        {evidence.acceptedCandidate && <p>Accepted candidate · {evidence.acceptedCandidate}</p>}
        {evidence.dispatch && <p>{evidence.dispatch}</p>}
        {evidence.delivery && <p>{evidence.delivery}</p>}
        {replacementId && <button type="button" className="guardrail-inspect"
          onClick={() => showInChat(replacementId)}>Inspect accepted replacement</button>}
      </>}
      <h3>API attempts</h3>
      {check.attempts.map((attempt, index) => <p key={index}>
        Attempt {index + 1} · {attempt.outcome} · API duration {attempt.duration} ms · {attempt.tokens === null ? "Token usage unavailable" : count(attempt.tokens, "token")}
        {" · "}{attempt.reportedModel ? "Reported model " + attempt.reportedModel : "Reported model unavailable"}
      </p>)}
    </div>
  </details>;
}

function storyState(scenario: GuardrailScenario) {
  const { checks, model, messages } = inspectionFixture(scenario);
  const base = callDetailsFixture(scenario === "restricted-history" ? "partial-archive" : "ended");
  if (base.status !== "ready") throw new Error("Call Details fixture must be available.");
  const snapshot = base.controller.details.getSnapshot();
  const timestamp = Date.parse(snapshot.call.startedAt ?? snapshot.call.createdAt);
  const turnsByTime = new Map<string, string>();
  const timeline: CallDetailsTimelineEntity[] = messages.map((message, index) => {
    // The preview uses unique fixture timestamps to find rendered rows; checks join on turn ID.
    const occurredAt = new Date(timestamp + (index + 1) * 1000).toISOString();
    turnsByTime.set(occurredAt, message.turn);
    const id = "message-" + message.turn;
    return { kind: "message", revision: 1, id, value: {
      id, turnId: message.turn, participantId: message.participantId, occurredAt, state: "final", text: message.text,
    } };
  });

  const owners = [...new Set(checks.map(check => check.agent))];
  const participants = [...snapshot.participants];
  if (owners.includes("routing")) {
    const assistant = participants.find(p => p.id === "assistant")!;
    participants.push({ ...assistant, id: "routing", value: { ...assistant.value, id: "routing", name: agents.routing } });
  }
  const metrics: MetricObservation[] = [...snapshot.metrics];
  for (const agent of owners) {
    const totals = summarize(checks.filter(check => check.agent === agent));
    const amounts: [string, number, string][] = [
      ["Evaluations", totals.evaluations, "Decisions"], ["API requests", totals.requests, "Decisions"],
    ];
    if (totals.rewrites) amounts.push(["Rewrites", totals.rewrites, "LLM"]);
    for (const [label, value, capability] of amounts) {
      metrics.push({ id: agent + label, revision: 1, value: { label, value, unit: "", source: capability,
        description: label + " for " + agents[agent], scope: { kind: "participant-capability", participantId: agent, capability } } });
    }
  }
  const details = createCallDetailsStore({ ...snapshot, timeline, participants, metrics });
  return { state: { ...base, controller: { details } }, turnsByTime, model, owners, checks,
    unassigned: checks.filter(check => !messages.some(message => message.turn === check.turn)),
  };
}

function Totals({ checks }: { checks: GuardrailCheck[] }) {
  const totals = summarize(checks);
  return <div className="guardrail-totals">
    <span>{count(totals.evaluations, "evaluation")}</span><span>{totals.blocked} blocked</span>
    {totals.errors > 0 && <span>{count(totals.errors, "checker error")}</span>}
    <span>{totals.failed === null ? "Question counts unavailable" : count(totals.failed, "failed question")}</span>
    <span>{count(totals.requests, "API request")}</span>
    {totals.retries > 0 && <span>{count(totals.retries, "transport retry", "transport retries")}</span>}
    {totals.rewrites > 0 && <span>{count(totals.rewrites, "LLM rewrite")}</span>}
  </div>;
}

type Target = { key: string; element: Element };

export function GuardrailCallDetails({ scenario, theme, initialTab = "Conversation" }: {
  scenario: GuardrailScenario; theme: "light" | "dark"; initialTab?: "Conversation" | "Metrics";
}) {
  const page = useMemo(() => storyState(scenario), [scenario]);
  const host = useRef<HTMLDivElement>(null);
  const [targets, setTargets] = useState<Target[]>([]);
  const [selected, setSelected] = useState<Agent | null>(null);
  const detailId = useId();
  const detailPanel = useRef<HTMLElement>(null);
  const [chatTarget, setChatTarget] = useState<string | null>(null);
  useLayoutEffect(() => { setSelected(null); }, [page]);
  useLayoutEffect(() => { if (selected) detailPanel.current?.focus(); }, [selected]);

  // The published page has no story slots. Keep this mount bridge local to the preview.
  useLayoutEffect(() => {
    const root = host.current!;
    function locate() {
      const next: Target[] = [];
      const metrics = root.querySelector(".vx-call-metrics");
      if (metrics) {
        next.push({ key: "metrics", element: metrics });
        for (const agent of page.owners) {
          const rowHeader = metrics.querySelector('th[scope="row"][aria-label="Decisions, ' + agents[agent] + '"]');
          if (rowHeader) next.push({ key: agent, element: rowHeader });
        }
      }
      const transcript = root.querySelector(".vx-transcript");
      if (transcript) {
        for (const time of transcript.querySelectorAll<HTMLTimeElement>("article time[datetime]")) {
          const turn = page.turnsByTime.get(time.dateTime);
          const body = time.closest("header")?.parentElement;
          if (turn && body) next.push({ key: turn, element: body });
        }
        if (page.unassigned.length) next.push({ key: "private", element: transcript });
      }
      setTargets(prev => prev.length === next.length && prev.every((v, i) => v.element === next[i].element && v.key === next[i].key) ? prev : next);
    }
    locate();
    const observer = new MutationObserver(locate);
    observer.observe(root, { childList: true, subtree: true });
    return () => observer.disconnect();
  }, [page]);

  useLayoutEffect(() => {
    if (!chatTarget) return;
    const target = host.current?.querySelector<HTMLDetailsElement>(".vx-transcript #evaluation-" + chatTarget);
    if (target) {
      target.open = true;
      target.querySelector("summary")?.focus();
      target.scrollIntoView?.({ block: "start" });
      setChatTarget(null);
    }
  }, [chatTarget, targets]);

  function showInChat(id: string) {
    const tabs = host.current?.querySelectorAll<HTMLButtonElement>('nav[aria-label="Call views"] button');
    Array.from(tabs ?? []).find(tab => tab.textContent === "Conversation")?.click();
    setChatTarget(id);
  }

  const checkDetails = (checks: GuardrailCheck[], inMetrics = false) => checks.map(check =>
    <CheckDetail key={check.id} check={check} model={page.model} inMetrics={inMetrics} showInChat={showInChat} />);
  return <div ref={host} className="guardrail-inspection">
    <CallDetailsPage state={page.state} theme={theme} initialTab={initialTab === "Metrics" ? "metrics" : "chat"}
      renderNavigationHeader={state => <StoryCallBreadcrumbs state={state} theme={theme} />} />
    {targets.map(({ key, element }) => {
      if (key === "metrics") return createPortal(<section className="guardrail-body" aria-label="Decisions detail">
        <h2>Decisions</h2><Totals checks={page.checks} />
        <div id={detailId}>{selected && <section tabIndex={-1} ref={detailPanel} aria-label={agents[selected] + " Decisions"}>
          <h3>{agents[selected]} · {page.model}</h3>
          {checkDetails(page.checks.filter(check => check.agent === selected), true)}
        </section>}</div>
      </section>, element, key);
      const agent = page.owners.find(owner => owner === key);
      if (agent) return createPortal(<button type="button" className="guardrail-inspect" aria-controls={detailId}
        aria-label={"Inspect Decisions for " + agents[agent]} aria-expanded={selected === agent}
        onClick={() => setSelected(current => current === agent ? null : agent)}>Inspect checks</button>, element, key);
      const owned = key === "private" ? page.unassigned : page.checks.filter(check => check.turn === key);
      if (!owned.length) return null;
      const label = key === "private" ? "Private call activity" : "Decisions";
      return createPortal(<section className="guardrail-body" aria-label={label}>
        <h2>{label}</h2>{checkDetails(owned)}
      </section>, element, key);
    })}
  </div>;
}
