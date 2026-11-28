import type { CallSpecSource, GuardrailEvent, GuardrailQuestion } from "./types";

// While a save is in flight the same editable row may be renamed, moved or edited.
// Keep its submitted object as its identity until the backend returns the saved ID.
const submittedRows = new WeakMap<GuardrailQuestion, GuardrailQuestion>();
const events: GuardrailEvent[] = ["before_turn", "after_turn", "before_outgoing_transfer"];

function* rows(source: CallSpecSource) {
  for (const [participant, value] of Object.entries(source.participants)) {
    if (value?.type !== "agent") continue;
    for (const event of events) {
      const questions = value.guardrails?.[event];
      if (!Array.isArray(questions)) continue;
      for (const [index, question] of questions.entries()) {
        if (question && typeof question === "object") yield { participant, event, index, question };
      }
    }
  }
}

export function hasUnsavedQuestions(source: CallSpecSource) {
  for (const { question } of rows(source)) if (!question.id) return true;
  return false;
}

export function savedIdsMatch(submitted: CallSpecSource, saved: CallSpecSource) {
  for (const { participant, event, index, question } of rows(submitted)) {
    if (question.id) continue;
    const stored = questionAt(saved, participant, event, index);
    if (!stored?.id || stored.question !== question.question || stored.required_answer !== question.required_answer) return false;
  }
  return true;
}

export function keepSubmittedRow(original: GuardrailQuestion, edited: GuardrailQuestion) {
  const submitted = submittedRows.get(original);
  if (submitted) submittedRows.set(edited, submitted);
  return edited;
}

function questionAt(source: CallSpecSource, participant: string, event: GuardrailEvent, index: number) {
  const value = source.participants[participant];
  return value?.type === "agent" ? value.guardrails?.[event]?.[index] : undefined;
}

export function copyEditableSource(source: CallSpecSource, forSave = false) {
  const copy = structuredClone(source);
  for (const { participant, event, index, question } of rows(source)) {
    if (question.id !== undefined) continue;
    if (forSave) submittedRows.set(question, question);
    keepSubmittedRow(question, questionAt(copy, participant, event, index)!);
  }
  return copy;
}

export function applySavedIds(submitted: CallSpecSource, saved: CallSpecSource, current: CallSpecSource) {
  const ids = new Map<GuardrailQuestion, string>();
  for (const { participant, event, index, question } of rows(submitted)) {
    const original = submittedRows.get(question);
    const id = questionAt(saved, participant, event, index)?.id;
    if (original && id) ids.set(original, id);
  }
  const next = copyEditableSource(current);
  for (const { question } of rows(next)) {
    const original = submittedRows.get(question);
    const id = original && ids.get(original);
    if (id) question.id = id;
  }
  return next;
}
