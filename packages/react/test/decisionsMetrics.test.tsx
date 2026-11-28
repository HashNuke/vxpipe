import { fireEvent, render, screen, within } from "@testing-library/react";
import type { GuardrailAttempt, GuardrailEvaluation, GuardrailQuestionResult } from "@vxpipe/core";
import { expect, test, vi } from "vitest";
import { Metrics } from "../src/Metrics.js";
import { createFixtureController } from "../stories/fixtureClient.js";

const snapshot = createFixtureController("conversation").getSnapshot();
const question = (id: string, outcome: "failed" | "passed", ordinal: number): GuardrailQuestionResult => ({
  id, ordinal, outcome, question: `Authored ${id}?`, requiredAnswer: "yes", thresholdHundredths: 70,
  inferredAnswer: outcome === "passed" ? "yes" : "no", probabilityYes: outcome === "passed" ? 0.8 : 0.6999,
});
const attempt = (id: string, values: Partial<GuardrailAttempt> = {}): GuardrailAttempt => ({
  id, ordinal: 0, outcome: "succeeded", durationMs: 80, ...values,
});
const evaluation = (id: string, values: Partial<GuardrailEvaluation> = {}): GuardrailEvaluation => ({
  id, participantId: "assistant", selectedProvider: "fixture", selectedModel: "policy-a",
  occurredAt: "2026-11-28T10:00:00Z", sourceTurnId: "turn-1", event: "after_turn", outcome: "passed",
  durationMs: 100, questions: [question("scope", "passed", 0)], attempts: [attempt(id + "-a")],
  ...values,
});

test("Decisions counts stable evaluations, authored question results and physical attempts separately", () => {
  const failed = Array.from({ length: 4 }, (_, index) => question(String(index), "failed", index));
  const denied = evaluation("blocked", { outcome: "blocked", questions: [...failed, failed[0]!, question("last", "passed", 4)] });
  const retry = attempt("retry", { ordinal: 1, retryOf: "original", inputTokens: 7, totalTokens: 7, model: "reported-b",
    costs: [{ currency: "USD", amount: "0.00001230" }, { currency: "EUR", amount: "0.00000000047" }] });
  const transfer = evaluation("handoff", { event: "before_outgoing_transfer", sourceTurnId: undefined,
    transferInvocationId: "native-move", attempts: [attempt("original", { outcome: "failed", errorCode: "rate_limited" }), retry, retry] });
  const onShowGuardrail = vi.fn();
  const checks = [evaluation("input", { event: "before_turn" }), denied, evaluation("repair"), transfer, denied];
  render(<Metrics theme="dark" snapshot={{ ...snapshot, metrics: [], guardrails: checks }} onShowGuardrail={onShowGuardrail} />);
  const row = screen.getByRole("rowheader", { name: "Decisions, Assistant, fixture · policy-a" });
  const section = screen.getByRole("region", { name: "Decisions detail" });
  for (const amount of ["4 evaluations", "1 blocked", "4 failed questions", "5 API requests", "1 transport retry"]) {
    expect(within(section).getByText(amount)).toBeVisible();
  }
  fireEvent.click(within(row).getByRole("button", { name: /Inspect checks/ }));
  const panel = within(section).getByRole("region", { name: "Assistant · fixture · policy-a" });
  const turn = within(panel).getByRole("region", { name: "Turn turn-1" });
  expect(within(turn).getByText("3 evaluations · 3 API requests")).toBeVisible();
  const invocation = within(panel).getByRole("region", { name: "Transfer native-move" });
  expect(within(invocation).getByText("1 evaluation · 2 API requests")).toBeVisible();
  const handoff = within(invocation).getByText("Before outgoing transfer").closest("details")!;
  fireEvent.click(handoff.querySelector("summary")!);
  expect(handoff).toHaveTextContent("Transfer native-move");
  expect(handoff).not.toHaveTextContent("turn-1");
  expect(handoff).toHaveTextContent("Rate limited");
  expect(handoff).toHaveTextContent("Token usage unavailable");
  expect(handoff).toHaveTextContent("Input 7 · Output unavailable · Total 7 tokens");
  expect(handoff).toHaveTextContent("reported-b");
  expect(handoff).toHaveTextContent("USD 0.00001230");
  expect(handoff).toHaveTextContent("EUR 0.00000000047");
  fireEvent.click(within(handoff).getByRole("button", { name: "Show evaluation in private activity" }));
  expect(onShowGuardrail).toHaveBeenCalledWith("handoff");
});

test("Decisions separates participant and model and protects restricted question details", () => {
  const secret = question("private", "failed", 0);
  const privateCheck = evaluation("secret", { contentUnavailable: "denied", outcome: "blocked",
    checkedText: "hidden draft", questions: [{ ...secret, feedback: "hidden feedback" }] });
  const others = [evaluation("other-model", { selectedModel: "policy-b", outcome: "cancelled", attempts: [] }),
    evaluation("other-person", { participantId: "routing", outcome: "error", attempts: [] })];
  render(<Metrics theme="light" snapshot={{ ...snapshot, metrics: [], guardrails: [privateCheck, ...others] }} />);
  expect(screen.getAllByRole("rowheader", { name: /^Decisions,/ })).toHaveLength(3);
  expect(screen.getByText("Question counts unavailable")).toBeVisible();
  expect(screen.getByText("1 checker error")).toBeVisible();
  expect(screen.getByText("1 cancellation")).toBeVisible();
  fireEvent.click(within(screen.getByRole("rowheader", { name: "Decisions, Assistant, fixture · policy-a" }))
    .getByRole("button", { name: /Inspect checks/ }));
  const details = screen.getByText("After turn").closest("details")!;
  fireEvent.click(details.querySelector("summary")!);
  expect(details).toHaveTextContent("Question details unavailable");
  expect(document.body).not.toHaveTextContent(/Authored private|hidden draft|hidden feedback/);
});

test("older calls with no guardrail metrics retain the existing empty state", () => {
  render(<Metrics theme="light" snapshot={{ ...snapshot, metrics: [] }} />);
  expect(screen.getByText("No metrics recorded.")).toBeVisible();
  expect(screen.queryByRole("region", { name: "Decisions detail" })).toBeNull();
});

test("missing private facts preserve authoritative request IDs, effective token corrections and other usage", () => {
  const incomplete = evaluation("partial", { outcome: "blocked", questionIds: ["a", "b"], questions: [question("a", "failed", 0)],
    attemptIds: ["submitted"], attempts: [] });
  const scope = { kind: "participant-capability", participantId: "assistant", capability: "Decisions" } as const;
  const metric = (label: string, value: number, attemptId: string, unit: string) => ({
    label, value, unit, attemptId, scope, source: "fixture", description: label,
  });
  const metrics = [metric("Requests", 1, "submitted", "requests"), metric("Input tokens", 0, "submitted", "tokens"),
    metric("Requests", 1, "unmatched", "requests"),
    { ...metric("Rewrites", 1, "model-attempt", "rewrites"), scope: { ...scope, capability: "LLM" } }];
  render(<Metrics theme="light" snapshot={{ ...snapshot, guardrails: [incomplete], metrics }} />);
  const selected = screen.getByRole("rowheader", { name: "Decisions, Assistant, fixture · policy-a" });
  const row = within(selected.closest("tr")!);
  expect(row.getByRole("button", { name: /^API requests .*: 1 reqs/ })).toBeVisible();
  expect(row.getByRole("button", { name: /^Input tokens .*: 0 tokens/ })).toBeVisible();
  expect(screen.getByText("Question counts unavailable")).toBeVisible();
  expect(screen.getByText("Retry count unavailable")).toBeVisible();
  expect(screen.getByText("2 API requests")).toBeVisible();
  expect(screen.getByText("1 LLM rewrite")).toBeVisible();
  const unmatched = screen.getByRole("rowheader", { name: "Decisions, Assistant" }).closest("tr")!;
  expect(within(unmatched).getByRole("button", { name: /^Requests .*: 1 reqs/ })).toBeVisible();
  expect(within(screen.getByRole("rowheader", { name: "LLM, Assistant" }).closest("tr")!)
    .getByRole("button", { name: /^Rewrites .*: 1 rewrites/ })).toBeVisible();
});

test("a reused physical ID on a different activation or turn cannot supplement this model's tokens", () => {
  const labeled = evaluation("owner", { activationId: "activation-a", responseTurnId: "response", attempts: [attempt("shared", { inputTokens: 3 })] });
  const metric = (activationId: string, turnId: string) => ({
    attemptId: "shared", label: "Input tokens", unit: "tokens", source: "fixture", description: "Input tokens",
    value: 97, activationId, turnId,
    scope: { kind: "participant-capability", participantId: "assistant", capability: "Decisions" } as const,
  });
  const metrics = [metric("activation-b", "response"), metric("activation-a", "other-turn")];
  render(<Metrics theme="light" snapshot={{ ...snapshot, metrics, guardrails: [labeled] }} />);
  const model = screen.getByRole("rowheader", { name: "Decisions, Assistant, fixture · policy-a" }).closest("tr")!;
  expect(within(model).getByRole("button", { name: /^Input tokens .*: 3 tokens/ })).toBeVisible();
  const usageOnly = screen.getByRole("rowheader", { name: "Decisions, Assistant" }).closest("tr")!;
  expect(within(usageOnly).getByRole("group", { name: /^Input tokens summary/ })).toHaveTextContent("194");
});

test("a restricted passing input belongs to its source turn and preserves the count of permitted failures", () => {
  const checks = [
    evaluation("input", { event: "before_turn", sourceTurnId: "input-turn", responseTurnId: "reply-turn",
      contentUnavailable: "denied", questions: [] }),
    evaluation("draft", { outcome: "blocked", sourceTurnId: "input-turn", responseTurnId: "reply-turn",
      questions: [question("restricted-account", "failed", 0)] }),
  ];
  render(<Metrics theme="dark" snapshot={{ ...snapshot, guardrails: checks }} />);
  expect(screen.getByText("1 failed question")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: /Inspect checks/ }));
  expect(within(screen.getByRole("region", { name: "Turn input-turn" })).getByText("Before turn")).toBeVisible();
  expect(within(screen.getByRole("region", { name: "Turn reply-turn" })).getByText("After turn")).toBeVisible();
  const turns = [...document.querySelectorAll(".vx-decisions-owner")];
  expect(turns.map(item => item.getAttribute("aria-label"))).toEqual(["Turn input-turn", "Turn reply-turn"]);
});

test("counts requests, retries and token amounts once per physical owner across reused IDs", () => {
  const first = evaluation("first", { activationId: "old", responseTurnId: "one",
    attempts: [attempt("request", { totalTokens: 3, costs: [{ currency: "USD", amount: "0.0003" }] })] });
  const second = evaluation("second", { activationId: "new", responseTurnId: "two",
    attempts: [attempt("request", { totalTokens: 5, costs: [{ currency: "USD", amount: "0.0005" }] }),
      attempt("retry", { ordinal: 1, retryOf: "request", totalTokens: 1 })] });
  const unattached = { activationId: "third", attemptId: "request", turnId: "three", label: "Requests",
    value: 1, unit: "requests", source: "fixture", description: "Requests",
    scope: { kind: "participant-capability", participantId: "assistant", capability: "Decisions" } as const };
  render(<Metrics theme="dark" snapshot={{ ...snapshot, guardrails: [first, second], metrics: [unattached] }} />);
  const panel = screen.getByRole("region", {name: "Decisions detail"});
  expect(within(panel).getByText("4 API requests")).toBeVisible();
  expect(within(panel).getByText("Retry count unavailable")).toBeVisible();
  const model = screen.getByRole("rowheader", {name: "Decisions, Assistant, fixture · policy-a"}).closest("tr")!;
  expect(within(model).getByRole("button", {name: /^API requests .*: 3 reqs/})).toBeVisible();
  expect(within(model).getByRole("button", {name: /^Total tokens .*: 9 tokens/})).toBeVisible();
  fireEvent.click(within(model).getByRole("button", {name: /Inspect checks/}));
  for (const [turn, amount] of [["one", "0.0003"], ["two", "0.0005"]]) {
    const own = within(panel).getByRole("region", {name:"Turn " + turn});
    fireEvent.click(own.querySelector("summary")!);
    expect(within(own).getByText("Cost USD " + amount)).toBeVisible();
  }
});

test("keeps unassigned native transfers distinct when a provider reuses its physical ID", () => {
  const transfer = (id: string, tokens: number) => evaluation(id, {
    event: "before_outgoing_transfer", activationId: "native", sourceTurnId: undefined, responseTurnId: undefined,
    transferInvocationId: id, attempts: [attempt("shared", { totalTokens: tokens })],
  });
  render(<Metrics theme="dark" snapshot={{ ...snapshot, metrics: [], guardrails: [transfer("billing", 2), transfer("sales", 6)] }} />);
  expect(screen.getByText("2 API requests")).toBeVisible();
  const row = screen.getByRole("rowheader", { name: "Decisions, Assistant, fixture · policy-a" }).closest("tr")!;
  expect(within(row).getByRole("button", { name: /^Total tokens .*: 8 tokens/ })).toBeVisible();
  fireEvent.click(within(row).getByRole("button", { name: /Inspect checks/ }));
  expect(screen.getByRole("region", { name: "Transfer billing" })).toBeVisible();
  expect(screen.getByRole("region", { name: "Transfer sales" })).toBeVisible();
});
