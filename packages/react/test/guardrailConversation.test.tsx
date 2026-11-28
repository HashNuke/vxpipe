import { fireEvent, render, screen, within } from "@testing-library/react";
import { expect, test } from "vitest";
import { createCallDetailsStore, type CallDetailsSnapshot, type GuardrailEvaluation } from "@vxpipe/core";
import { groupDecisions } from "../src/decisionsMetrics.js";
import { CallConsole } from "../src/index.js";
import { createFixtureController } from "../stories/fixtureClient.js";

const time = (second: number) => new Date(Date.UTC(2026, 8, 16, 8, 0, second)).toISOString();

function evaluation(id: string, fields: Partial<GuardrailEvaluation>): GuardrailEvaluation {
  return {
    id, occurredAt: time(3), event: "after_turn", outcome: "blocked",
    participantId: "assistant", activationId: "activation", responseTurnId: "turn",
    attempts: [], questions: [{
      id: "scope", ordinal: 0, outcome: "failed", requiredAnswer: "yes",
      probabilityYes: 0.6999, inferredAnswer: "no", thresholdHundredths: 70, question: id + " question?",
    }], ...fields,
  };
}

function inspect(checks: GuardrailEvaluation[], extraTimeline: CallDetailsSnapshot["timeline"] = [],
  metrics?: CallDetailsSnapshot["metrics"]) {
  const base = createFixtureController("conversation").details.getSnapshot();
  const timeline: CallDetailsSnapshot["timeline"] = [
    { id: "input", kind: "message", revision: 1, value: { id: "input", participantId: "caller", turnId: "turn", text: "Real input.", occurredAt: time(1), state: "final" }},
    { id: "reply", kind: "message", revision: 1, value: { id: "reply", participantId: "assistant", turnId: "turn", text: "Released response.", occurredAt: time(5), state: "final" }},
    ...extraTimeline,
  ];
  const details = createCallDetailsStore({...base, ...(metrics ? {metrics, metricsAvailability: {state:"available" as const}} : {}), timeline, guardrails: checks.map(value => ({id: value.id, revision: 1, value}))});
  render(<CallConsole inspectConversation controller={{details}} />);
  return details;
}

async function select(label: string, value: string) {
  const trigger = within(screen.getByRole("dialog")).getByRole("combobox", {name: label});
  fireEvent.keyDown(trigger, {key: "Enter"});
  fireEvent.click(await screen.findByRole("option", {name: value}));
}

test("the production Conversation shows one withheld mixed attempt and links each stage to its own speaker", async () => {
  inspect([
    evaluation("input-score", {event: "before_turn", sourceParticipantId: "caller", sourceTurnId: "turn", messageId: "input"}),
    evaluation("draft", {candidateAttemptId: "turn:1", checkedText: "Withheld speech.", proposedTools: [{id:"lookup",name:"lookup_account"}]}),
    evaluation("transfer", {event: "before_outgoing_transfer", candidateAttemptId: "turn:1", transferInvocationId: "route"}),
    evaluation("retry", {outcome: "passed", candidateAttemptId: "turn:2", checkedText: "Released response.", questions: []}),
  ]);
  const caller = within(screen.getByText("Real input.").closest("article")!);
  expect(caller.getByText("input-score question?")).toBeVisible();
  expect(caller.queryByText("draft question?")).toBeNull();
  const draft = within(screen.getByText("Withheld speech.").closest("article")!);
  expect(draft.getByText("Unsent")).toBeVisible();
  expect(draft.getByText("lookup_account")).toBeVisible();
  expect(draft.getByText("transfer question?")).toBeVisible();
  fireEvent.click(draft.getByRole("button", {name: /Failed.*draft question/}));
  expect(draft.getByRole("tooltip")).toHaveTextContent("0.6999 < 0.70");
  fireEvent.click(screen.getByRole("button", {name: "Filters"}));
  expect(within(screen.getByRole("dialog")).getAllByRole("combobox")).toHaveLength(5);
  await select("Guardrails", "Hide");
  fireEvent.click(screen.getByRole("button", {name: "Close dialog"}));
  expect(screen.queryByText("Withheld speech.")).toBeNull();
  expect(screen.queryByText("lookup_account")).toBeNull();
  expect(screen.getByText("Real input.")).toBeVisible();
  expect(screen.getByText("Released response.")).toBeVisible();
});

test("a denied evaluation never reuses checked text or a question from another agent or retry", () => {
  inspect([
    evaluation("denied", {participantId: "private-agent", activationId: "other", candidateAttemptId: "turn:1",
      contentUnavailable: "denied", checkedText: "Forbidden retained text."}),
    evaluation("allowed", {candidateAttemptId: "turn:1", checkedText: "Permitted private draft."}),
  ]);
  expect(screen.getByText("Question details unavailable")).toBeVisible();
  expect(screen.queryByText("Forbidden retained text.")).toBeNull();
  expect(screen.queryByText("denied question?")).toBeNull();
  const permitted = within(screen.getByText("Permitted private draft.").closest("article")!);
  expect(permitted.queryByText("Question details unavailable")).toBeNull();
  expect(permitted.getByText("allowed question?")).toBeVisible();
});


test("attaches only the explicitly linked attempt and preserves an independently completed tool", async () => {
  inspect([
    evaluation("earlier", {outcome: "passed", checkedText: "Different checked text.", candidateAttemptId: "first"}),
    evaluation("released", {outcome: "passed", checkedText: "Released response.", candidateAttemptId: "second",
      messageId: "reply", deliveredFactId: "delivery"}),
    evaluation("blocked-transfer", {event: "before_outgoing_transfer", transferInvocationId: "reused", candidateAttemptId: "third"}),
  ], [{kind: "tool-call", id: "reused", revision: 1, value: {id: "reused", name: "completed_lookup",
    status: "completed", occurredAt: time(2)}}]);
  expect(screen.getByText("completed_lookup")).toBeVisible();
  fireEvent.click(screen.getByRole("button", {name: "Filters"}));
  await select("Guardrails", "All");
  fireEvent.click(screen.getByRole("button", {name: "Close dialog"}));
  const publicReply = within(screen.getByText("Released response.").closest("article")!);
  expect(publicReply.getByText("released question?")).toBeVisible();
  expect(publicReply.queryByText("earlier question?")).toBeNull();
  const earlier = within(screen.getByText("Different checked text.").closest("article")!);
  expect(earlier.getByText("earlier question?")).toBeVisible();
  expect(earlier.getByText("Checked candidate")).toBeVisible();
});

test("an allowed mixed attempt keeps its questions on a visible owner when messages are filtered out", async () => {
  inspect([
    evaluation("after", {outcome: "passed", commandId:"cmd", candidateAttemptId: "mixed", messageId: "reply"}),
    evaluation("transfer", {event: "before_outgoing_transfer", outcome: "passed", commandId:"cmd", candidateAttemptId: "mixed",
      transferOutcome: "completed", transferInvocationId: "invocation"}),
  ], [{kind: "tool-call", id: "scoped-tool", revision: 1, value: {id: "scoped-tool", toolCallId:"invocation", participantId:"assistant", activationId:"activation", commandId:"cmd", name: "participant_transfer",
    status: "completed", occurredAt: time(3)}}]);
  fireEvent.click(screen.getByRole("button", {name: "Filters"}));
  await select("Guardrails", "All");
  await select("Messages", "Hide");
  fireEvent.click(screen.getByRole("button", {name: "Close dialog"}));
  const tool = within(screen.getByText("participant_transfer").closest(".vx-timeline-tool")! as HTMLElement);
  expect(tool.getByText("after question?")).toBeVisible();
  expect(tool.getByText("transfer question?")).toBeVisible();
});

test("a transfer-only check owns its permitted speech and requested destination", () => {
  inspect([evaluation("only-transfer", {event: "before_outgoing_transfer", candidateAttemptId: "transfer-draft",
    checkedText: "I will transfer you.", transferInvocationId: "try-billing", requestedDestination: "Billing"})]);
  const draft = within(screen.getByText("I will transfer you.").closest("article")!);
  expect(draft.getByText("Transfer to Billing")).toBeVisible();
  expect(draft.getByText("Unsent")).toBeVisible();
  expect(draft.getByText("only-transfer question?")).toBeVisible();
});

test("Only failures omits an empty question card without exposing successful questions", async () => {
  inspect([evaluation("inconsistent", {candidateAttemptId: "check", checkedText: "Withheld.",
    questions: [{id: "q", ordinal: 1, question: "Allowed question?", outcome: "passed", requiredAnswer: "yes", thresholdHundredths: 50}]})]);
  expect(screen.getByText("Withheld.")).toBeVisible();
  expect(screen.queryByRole("region", {name: "After turn · Assistant"})).toBeNull();
  expect(screen.queryByText("After turn")).toBeNull();
});

test("delivery and transfer status in the Conversation follow actual archive receipts", async () => {
  inspect([
    evaluation("accepted", {outcome: "passed", checkedText: "No receipt yet."}),
    evaluation("delivered", {outcome: "passed", messageId: "reply", deliveredFactId: "actual-delivery"}),
    evaluation("attempted-transfer", {event: "before_outgoing_transfer", outcome: "passed", transferInvocationId: "tool",
      transferOutcome: "failed"}),
  ]);
  fireEvent.click(screen.getByRole("button", {name: "Filters"}));
  await select("Guardrails", "All");
  fireEvent.click(screen.getByRole("button", {name: "Close dialog"}));
  const delivered = within(screen.getByText("Released response.").closest("article")!);
  expect(delivered.getByText("Delivery confirmed")).toBeVisible();
  const accepted = within(screen.getByText("No receipt yet.").closest("article")!);
  expect(accepted.getByText("Candidate accepted")).toBeVisible();
  expect(accepted.queryByText("Delivery confirmed")).toBeNull();
  expect(screen.getByText("Transfer failed")).toBeVisible();
});

test("a checked input without its own message receipt remains private even if another command reuses the turn", () => {
  inspect([evaluation("unlinked-input", {event: "before_turn", sourceParticipantId: "caller", sourceTurnId: "turn",
    checkedText: "Independently retained input."})]);
  const publicInput = within(screen.getByText("Real input.").closest("article")!);
  expect(publicInput.queryByText("unlinked-input question?")).toBeNull();
  const privateInput = within(screen.getByText("Independently retained input.").closest("article")!);
  expect(privateInput.getByText("Checked input")).toBeVisible();
  expect(privateInput.getByText("unlinked-input question?")).toBeVisible();
  expect(privateInput.getByText("Caller")).toBeVisible();
  expect(privateInput.queryByText("Unsent")).toBeNull();
});


test("a denied transfer cannot hide a different command's failed invocation with the same provider ID", () => {
  inspect([evaluation("denied", {event:"before_outgoing_transfer", commandId:"new-command", transferInvocationId:"reused"})],
    [{id:"reused", kind:"tool-call", revision:1, value:{id:"reused", toolCallId:"reused", participantId:"assistant",
      activationId:"activation", commandId:"previous-command", name:"previous-failed-lookup", status:"failed", occurredAt:time(2)}}]);
  expect(screen.getByText("previous-failed-lookup")).toBeVisible();
});

test("the message tooltip shows only this check's measured attempts on the owning source message", async () => {
  const check = evaluation("input-score", {event:"before_turn", sourceTurnId:"turn", sourceParticipantId:"caller",
    messageId:"input", responseTurnId:"other-turn", attemptIds:["a1", "a2", "a3"]});
  const metric = (id:string, attemptId:string, activationId:string, turnId:string, value:number) => ({
    id, revision:1, value:{label:"Input tokens", value, unit:"tokens", source:"Provider", description:"Input tokens",
      activationId, turnId, attemptId, scope:{kind:"participant-capability" as const, capability:"Decisions", participantId:"assistant"}}});
  inspect([check], [], [
    metric("m1","a1","activation","turn",12),metric("m2","a2","activation","turn",13),
    metric("other","a1","different","turn",99),metric("unlinked","unlinked","activation","turn",98),
    metric("wrong-turn","a1","activation","other-turn",97)
  ]);
  const input = within(screen.getByText("Real input.").closest("article")!);
  const reply = within(screen.getByText("Released response.").closest("article")!);
  fireEvent.focus(input.getByRole("button",{name:/View metrics/}));
  const tooltip = await screen.findByRole("tooltip");
  expect(tooltip).toHaveTextContent("Decisions");
  expect(tooltip).toHaveTextContent("12");
  expect(tooltip).toHaveTextContent("13");
  expect(tooltip).not.toHaveTextContent(/99|98|97/);
  expect(reply.getByRole("button",{name:/Metrics unavailable/})).toBeDisabled();
});

test("an unassigned transfer's amounts require its exact invocation", () => {
  const native = evaluation("native", {event:"before_outgoing_transfer", sourceTurnId:undefined, responseTurnId:undefined,
    transferInvocationId:"handoff-A", attemptIds:["submitted"]});
  const base = {label:"Requests", unit:"requests", value:1, source:"Provider", description:"Requests",
    attemptId:"submitted", activationId:"activation", scope:{kind:"participant-capability" as const, capability:"Decisions", participantId:"assistant"}};
  const matched = {...base, toolCallId:"handoff-A"};
  const other = {...base, toolCallId:"handoff-B"};
  expect(groupDecisions([native],[matched,other,base]).otherMetrics).toEqual([other,base]);
});
