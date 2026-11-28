import { editSource } from "./editSource";
import { agent } from "./edits";
import type { GuardrailEvent, GuardrailQuestion, SourceDocument } from "./types";

export const guardrailEvents: GuardrailEvent[] = ["before_turn", "after_turn", "before_outgoing_transfer"];
export const guardrailEventTitles: Record<GuardrailEvent, string> = {
  before_turn: "Before turn",
  after_turn: "After turn",
  before_outgoing_transfer: "Before outgoing transfer",
};

/** Backend assigns question IDs on save; the editor never invents them. */
export function setGuardrailQuestions(
  document: SourceDocument,
  participantKey: string,
  event: GuardrailEvent,
  questions: GuardrailQuestion[],
): SourceDocument {
  return editSource(document, (source) => {
    const target = agent(source, participantKey);
    const guardrails = (target.guardrails ??= {});
    if (questions.length) guardrails[event] = questions;
    else delete guardrails[event];
    if (!Object.keys(guardrails).length) delete target.guardrails;
  });
}

export function moveGuardrailQuestion(
  current: GuardrailQuestion[],
  index: number,
  direction: -1 | 1,
): GuardrailQuestion[] {
  const target = index + direction;
  if (index < 0 || index >= current.length || target < 0 || target >= current.length) return current;
  const next = current.slice();
  const [moved] = next.splice(index, 1);
  next.splice(target, 0, moved!);
  return next;
}

/** Two-decimal canonical display for an authored threshold; empty resolves to the 0.70 default on save. */
export function formatThreshold(value: number | undefined): string {
  return value === undefined ? "" : value.toFixed(2);
}

export function parseThreshold(input: string): number | undefined | null {
  const trimmed = input.trim();
  if (!trimmed) return undefined;
  if (!/^(0(\.\d{1,2})?|1(\.0{1,2})?)$/.test(trimmed)) return null;
  return Number(trimmed);
}

export function passPreview(threshold: number | undefined, required: "yes" | "no" | undefined): string {
  if (required === undefined) return "Choose Yes or No to preview when this passes.";
  const effective = threshold ?? 0.7;
  const text = effective.toFixed(2);
  if (effective === 0)
    return required === "yes"
      ? "Always passes: P(Yes) ≥ 0.00 always holds, so Yes is always inferred."
      : "Always fails: P(Yes) ≥ 0.00 always holds, so Yes is always inferred.";
  if (effective === 1) return required === "yes" ? "Passes only when P(Yes) = 1.00." : "Passes when P(Yes) < 1.00; a score of exactly 1.00 fails.";
  return required === "no" ? `Passes when P(Yes) < ${text}` : `Passes when P(Yes) ≥ ${text}`;
}
