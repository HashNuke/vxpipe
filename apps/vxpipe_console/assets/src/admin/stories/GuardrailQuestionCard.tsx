import { useEffect, useId, useRef, useState } from "react";
import { Check, Minus, X } from "lucide-react";
import { agents, type GuardrailCheck, type QuestionResult } from "./guardrailInspectionFixtures";

function ResultIcon({ q }: {q: QuestionResult}) {
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
  const probability = q.probability;
  const score = probability !== null && Number(probability.toFixed(2)) === probability
    ? probability.toFixed(2) : String(probability);
  const Icon = q.outcome === "Passed" ? Check : q.outcome === "Failed" ? X : Minus;
  const comparison = q.probability === q.threshold ? "=" : (q.probability ?? 0) < q.threshold ? "<" : ">";
  return <span ref={anchor} className="gh-result" data-outcome={q.outcome}
    onPointerEnter={e => { if (e.pointerType === "mouse") setOpen(true); }}
    onPointerLeave={e => { if (e.pointerType === "mouse") setOpen(false); }}>
    <button type="button" aria-label={q.outcome + " · " + q.question} aria-describedby={open ? id : undefined}
      onPointerDown={e => { touchWasOpen.current = e.pointerType === "touch" && open; }}
      onFocus={() => setOpen(true)} onBlur={() => setOpen(false)}
      onClick={() => { setOpen(!touchWasOpen.current); touchWasOpen.current = false; }}
      onKeyDown={e => { if (e.key === "Escape") setOpen(false); }}><Icon size={15} aria-hidden="true" /></button>
    {open && <span id={id} role="tooltip" className="gh-tooltip"><strong>{q.outcome}</strong> · Required {q.required}
      <span>P(Yes) {q.probability === null ? "unavailable" : score + " " + comparison + " "}
        {q.probability !== null && <span className="gh-threshold">{q.threshold.toFixed(2)}<span className="sr-only"> threshold</span></span>}</span>
      {q.probability === q.threshold && <span>At threshold · Answer Yes</span>}
    </span>}
  </span>;
}

export function GuardrailQuestionCard({ check, all, showAgent }: {check: GuardrailCheck; all: boolean; showAgent: boolean}) {
  const questions = check.evidence?.questions.filter(q => all || q.outcome === "Failed");
  return <section id={"evaluation-" + check.id} tabIndex={-1} className="gh-card" aria-label={check.event + " · " + agents[check.agent]}>
    <h3>{check.event}{showAgent && <span> · {agents[check.agent]}</span>}</h3>
    {check.status === "Error" && <small>Check incomplete</small>}
    {questions ? <ul>{questions.map(q => <li key={q.id}><ResultIcon q={q} /><span>{q.question}</span></li>)}</ul>
      : <small>Question details unavailable</small>}
  </section>;
}
