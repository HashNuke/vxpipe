import { useId, useLayoutEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { createCallDetailsStore, type MetricObservation } from "@vxpipe/core";
import { CallDetailsPage } from "../CallDetailsPage";
import { callDetailsFixture } from "../callDetailsFixtures";
import { StoryCallBreadcrumbs } from "./StoryCallBreadcrumbs";
import { agents, inspectionFixture, type Agent, type GuardrailCheck, type GuardrailScenario } from "./guardrailInspectionFixtures";
import { HistoryFilterButton, presets, type HistoryFilters } from "./GuardrailHistoryFilters";
import { GuardrailQuestionCard } from "./GuardrailQuestionCard";
import { historyTimeline } from "./guardrailHistoryTimeline";
import { Wrench } from "lucide-react";
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

function storyState(scenario: GuardrailScenario, filters: HistoryFilters) {
  const { checks, model } = inspectionFixture(scenario);
  const base = callDetailsFixture(scenario === "restricted-history" ? "partial-archive" : "ended");
  if (base.status !== "ready") throw new Error("Call Details fixture must be available.");
  const snapshot = base.controller.details.getSnapshot();
  const timestamp = Date.parse(snapshot.call.startedAt ?? snapshot.call.createdAt);
  const {timeline, annotations} = historyTimeline(scenario, timestamp, filters);
  for (const item of snapshot.timeline) {
    if (item.kind === "activity" && filters.events && (filters.technical || item.id === "activity-1")) timeline.push(item);
    if (item.kind === "protocol-event" && filters.logs) timeline.push(item);
    if (item.kind === "tool-call" && filters.tools && scenario === "repair-and-transfer") {
      const { request, response, responseStatus, ...summary } = item.value;
      timeline.push(filters.toolDetails ? item : { ...item, value: summary });
    }
  }

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
  return { state: { ...base, controller: { details } }, annotations, model, owners, checks,
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
  return <Preview key={scenario} scenario={scenario} theme={theme} initialTab={initialTab} />;
}

function Preview({ scenario, theme, initialTab }: {
  scenario: GuardrailScenario; theme: "light" | "dark"; initialTab: "Conversation" | "Metrics";
}) {
  const [filters, change] = useState<HistoryFilters>(() =>
    scenario === "pass" || scenario === "partial-answer" || scenario === "multiple-agents" ? presets.All : presets.Debug);
  const page = useMemo(() => storyState(scenario, filters), [scenario, filters]);
  const host = useRef<HTMLDivElement>(null);
  const [targets, setTargets] = useState<Target[]>([]);
  const [selected, setSelected] = useState<Agent | null>(null);
  const detailId = useId();
  const detailPanel = useRef<HTMLElement>(null);
  const [chatTarget, setChatTarget] = useState<string | null>(null);
  useLayoutEffect(() => { setSelected(null); }, [scenario]);
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
        const controls = root.querySelector(".vx-conversation-filter-controls");
        if (controls) {
          next.push({key: "filters", element: controls});
          // The story projects its filtered activities into the standard Console renderer.
          for (const label of ["Events", "Technical events", "Logs"]) {
            controls.querySelector<HTMLButtonElement>('button[aria-label="Show ' + label + '"]')?.click();
          }
        }
        for (const time of transcript.querySelectorAll<HTMLTimeElement>("time[datetime]")) {
          const annotation = page.annotations.get(time.dateTime);
          if (!annotation) continue;
          const body = annotation.anchor === "message" ? time.closest("article")?.querySelector("header")?.parentElement :
            annotation.anchor === "tool" ? time.closest(".vx-timeline-tool") : time.closest(".vx-timeline-activity");
          const label = body?.querySelector(annotation.anchor === "message" ? ":scope > p" :
            annotation.anchor === "tool" ? ".vx-tool-summary strong" : ":scope > span")?.textContent;
          if (body && label === annotation.label) next.push({ key: time.dateTime, element: body });
        }
        if (transcript.querySelector(".vx-empty")) next.push({key: "empty", element: transcript});
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
    const target = host.current?.querySelector<HTMLElement>(".vx-transcript #evaluation-" + chatTarget);
    if (target) {
      target.focus();
      target.scrollIntoView?.({ block: "start" });
      setChatTarget(null);
    }
  }, [chatTarget, targets]);

  function showInChat(id: string) {
    change(presets.All);
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
      if (key === "filters") return createPortal(<HistoryFilterButton filters={filters} change={change} />, element, key);
      if (key === "empty") return createPortal(<div className="gh-empty">
        <p>No matching history</p><button type="button" className="gh-reset" onClick={() => change(presets.All)}>Show all history</button>
      </div>, element, key);
      const row = page.annotations.get(key);
      if (!row) return null;
      return createPortal(<div className="gh-annotation" data-blocked={row.blocked}>
        {row.unsent && <span className="gh-status">Unsent</span>}
        {row.toolOnly && row.blocked && !row.tools.length && <span className="gh-status">Not run</span>}
        {row.tools.map(tool => <div className="gh-proposed-tool" key={tool.id}>
          {filters.toolDetails ? <details><summary><Wrench size={13} /> <strong>{tool.name}</strong> · Not run</summary>
            <pre>{JSON.stringify(tool.arguments, null, 2)}</pre></details> :
            <span><Wrench size={13} /> <strong>{tool.name}</strong> · Not run</span>}
        </div>)}
        {row.checks.map(check => <GuardrailQuestionCard key={check.id} check={check} all={filters.guardrails === "All"}
          showAgent={page.owners.length > 1} />)}
      </div>, element, key);
    })}
  </div>;
}
