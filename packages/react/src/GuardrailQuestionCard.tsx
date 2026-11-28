import { useEffect, useId, useRef, useState } from "react";
import { Check, Minus, X } from "lucide-react";
import type { GuardrailEvaluation, GuardrailQuestionResult } from "@vxpipe/core";

const stages = {
  before_turn: "Before turn",
  after_turn: "After turn",
  before_outgoing_transfer: "Before outgoing transfer",
};

function recordedStatus(check: GuardrailEvaluation) {
  if (check.outcome === "error") return "Check incomplete";
  if (check.outcome === "cancelled") return "Check cancelled";
  if (check.outcome === "pending") return "Check pending";
  if (check.outcome === "skipped_empty") return "No configured questions";
  if (check.outcome === "not_applicable") return "Check not applicable";
  if (check.event === "after_turn" && check.outcome === "passed") {
    return check.deliveredFactId ? "Delivery confirmed" : "Candidate accepted";
  }
  if (check.event === "before_outgoing_transfer" && check.transferOutcome) {
    return check.transferOutcome === "completed" ? "Transfer completed" : "Transfer failed";
  }
}
const title = (text: string) => text[0]!.toUpperCase() + text.slice(1);

function ResultIcon({ q }: {q: GuardrailQuestionResult}) {
  const [open, setOpen] = useState(false);
  const id = useId();
  const anchor = useRef<HTMLSpanElement>(null);
  const touchWasOpen = useRef(false);
  useEffect(() => {
    if (!open) return;
    function outside(event: PointerEvent) {
      if (event.target instanceof Node && !anchor.current?.contains(event.target)) setOpen(false);
    }
    document.addEventListener("pointerdown", outside);
    return () => document.removeEventListener("pointerdown", outside);
  }, [open]);
  const probability = q.probabilityYes;
  const threshold = q.thresholdHundredths / 100;
  const score = probability !== undefined && Number(probability.toFixed(2)) === probability
    ? probability.toFixed(2) : String(probability);
  const Icon = q.outcome === "passed" ? Check : q.outcome === "failed" ? X : Minus;
  const comparison = probability === threshold ? "=" : (probability ?? 0) < threshold ? "<" : ">";
  return <span ref={anchor} className="vx-guardrail-result" data-outcome={title(q.outcome)}
    onPointerEnter={e => { if (e.pointerType === "mouse") setOpen(true); }}
    onPointerLeave={e => { if (e.pointerType === "mouse") setOpen(false); }}>
    <button type="button" aria-label={title(q.outcome) + " · " + (q.question ?? "Question unavailable")} aria-describedby={open ? id : undefined}
      onPointerDown={e => { touchWasOpen.current = e.pointerType === "touch" && open; }}
      onFocus={() => setOpen(true)} onBlur={() => setOpen(false)}
      onClick={() => { setOpen(!touchWasOpen.current); touchWasOpen.current = false; }}
      onKeyDown={e => { if (e.key === "Escape") setOpen(false); }}><Icon size={15} aria-hidden="true" /></button>
    {open && <span id={id} role="tooltip" className="vx-guardrail-tooltip"><strong>{title(q.outcome)}</strong> · Required {title(q.requiredAnswer)}
      <span>P(Yes) {probability === undefined ? "unavailable" : score + " " + comparison + " "}
        {probability !== undefined && <span className="vx-guardrail-threshold">{threshold.toFixed(2)}<span className="sr-only"> threshold</span></span>}</span>
      {probability === threshold && <span>At threshold · Answer Yes</span>}
    </span>}
  </span>;
}

export function GuardrailQuestionCard({check, all, agent, showAgent, focus}: {
  check: GuardrailEvaluation; all: boolean; agent: string; showAgent: boolean; focus: boolean;
}) {
  const card = useRef<HTMLElement>(null);
  useEffect(() => {
    if (focus) { card.current?.focus(); card.current?.scrollIntoView?.({block: "nearest"}); }
  }, [focus]);
  const stage = stages[check.event];
  const permitted = !check.contentUnavailable;
  const questions = permitted
    ? check.questions.filter(q => all || q.outcome === "failed").sort((a, b) => a.ordinal - b.ordinal)
    : [];
  const status = recordedStatus(check);
  const missingQuestions = !permitted || (!check.questions.length &&
    check.outcome !== "skipped_empty" && check.outcome !== "not_applicable");
  if (permitted && !all && check.questions.length && !questions.length && check.outcome === "blocked") return null;
  return <section ref={card} id={"evaluation-" + check.id} tabIndex={-1} className="vx-guardrail-card" aria-label={stage + " · " + agent}>
    <h3>{stage}{showAgent && <span> · {agent}</span>}</h3>
    {status && <small>{status}</small>}
    {missingQuestions ? <small>Question details unavailable</small> : questions.length > 0 &&
      <ul>{questions.map(q => <li key={q.id}>
        {q.question ? <><ResultIcon q={q} /><span>{q.question}</span></> : <small>Question details unavailable</small>}
      </li>)}</ul>}
  </section>;
}
