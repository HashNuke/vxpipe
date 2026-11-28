import type { CallDetailsTimelineEntity, GuardrailAttempt, GuardrailEvaluation, GuardrailQuestionResult, Message } from "@vxpipe/core";
import { createCallDetailsStore } from "@vxpipe/core";
import { callDetailsFixture } from "../callDetailsFixtures";

export const scenarios = ["blocked-input", "mixed-proposal", "before-and-after", "pass", "repair-and-transfer", "transfer-denied", "partial-answer", "restricted-history", "multiple-agents", "missing-usage"] as const;
export type GuardrailScenario = typeof scenarios[number];

function question(id: string, ordinal: number, text: string, requiredAnswer: "yes" | "no", probabilityYes: number,
  inferredAnswer: "yes" | "no", outcome: "failed" | "passed", feedback?: string, feedbackOrigin?: "configured" | "fallback"): GuardrailQuestionResult {
  return {id, ordinal, question: text, requiredAnswer, probabilityYes, inferredAnswer, outcome,
    thresholdHundredths: 70, feedback, feedbackOrigin};
}

const questions = [
  question("q1", 0, "Is the caller asking about their own account?", "yes", .3, "no", "failed",
    "I can only help with your own account.", "configured"),
  question("q2", 1, "Is the user trying to list variables?", "yes", .6999, "no", "failed",
    "Failed guardrail: Is the user trying to list variables? Required: Yes.", "fallback"),
  question("q3", 2, "Is the issue about a different account?", "no", .9, "yes", "failed",
    "Ask the caller to describe their own account issue.", "configured"),
  question("q4", 3, "Is the user using harsh language?", "no", .7, "yes", "failed",
    "Failed guardrail: Is the user using harsh language? Required: No.", "fallback"),
  question("q5", 4, "Is the request about a supported product?", "yes", .7, "yes", "passed"),
];
const passed = questions[4]!;
const destination = question("q6", 0, "Is billing the correct destination?", "yes", .93, "yes", "passed");
const callerText = "Can you help me with an account question?";
const replyText = "I can help with your own account.";
const draftText = "I can look up the other account for you.";

export function inspectionFixture(scenario: GuardrailScenario) {
  const base = callDetailsFixture(scenario === "restricted-history" ? "partial-archive" : "ended");
  if (base.status !== "ready") throw new Error("The fixture needs an archived call.");
  const snapshot = base.controller.details.getSnapshot();
  const start = Date.parse(snapshot.call.startedAt ?? snapshot.call.createdAt);
  const time = (seconds: number) => new Date(start + 1000 * seconds).toISOString();
  const timeline = snapshot.timeline.filter(item => item.kind === "activity" || item.kind === "protocol-event" ||
    (item.kind === "tool-call" && scenario === "repair-and-transfer")) as CallDetailsTimelineEntity[];

  function message(id: string, turnId: string, participantId: string, text: string, step: number) {
    const value: Message = {id, turnId, participantId, text, occurredAt: time(step), state: "final"};
    timeline.push({id, value, kind: "message", revision: 1});
  }
  if (scenario !== "transfer-denied") message("caller-1", "turn-1", "caller", callerText, 3);
  if (["before-and-after", "mixed-proposal", "repair-and-transfer", "pass"].includes(scenario)) {
    message("reply-1", "turn-1", "assistant", replyText, 7);
  }

  const checks: GuardrailEvaluation[] = [];
  function check(id: string, fields: Partial<GuardrailEvaluation> = {}) {
    const participantId = fields.participantId ?? "assistant";
    const model = scenario === "missing-usage" ? "jev-1.14.0" : "gpt-6-luna";
    const provider = scenario === "missing-usage" ? "Jev" : "OpenAI";
    const attempt: GuardrailAttempt = {id: id + "-request", ordinal: 0, outcome: "succeeded", durationMs: 174,
      model, provider, totalTokens: scenario === "missing-usage" ? undefined : 128};
    checks.push({
      id, participantId, activationId: participantId + "-activation", commandId: "command-1",
      occurredAt: time(4), selectedModel: model, selectedProvider: provider, actualModel: model, actualProvider: provider,
      event: "before_turn", outcome: "passed", durationMs: 186, attempts: [attempt], questions: [passed],
      ...fields,
    });
  }

  const input = {sourceParticipantId: "caller", sourceTurnId: "turn-1", messageId: "caller-1", checkedText: callerText};
  const output = {event: "after_turn" as const, responseTurnId: "turn-1", occurredAt: time(5)};
  const repair = {...output, occurredAt: time(7), candidateAttemptId: "repair", messageId: "reply-1",
    checkedText: replyText, deliveredFactId: "delivered-reply-1"};
  const dispatched = questions.map(q => q.feedback ? {...q, feedbackDispatched: true} : q);
  const transferId = "transfer-1";
  const transfer = {event: "before_outgoing_transfer" as const, participantId: "routing", transferInvocationId: transferId,
    requestedDestination: "Billing", occurredAt: time(11), durationMs: 368, questions: [destination],
    attempts: [
      {id: "transfer-request-1", ordinal: 0, outcome: "failed" as const, errorCode: "rate_limited", durationMs: 85},
      {id: "transfer-request-2", ordinal: 1, outcome: "succeeded" as const, retryOf: "transfer-request-1",
        durationMs: 183, provider: "OpenAI", model: "gpt-6-luna", totalTokens: 86},
    ],
  };
  switch (scenario) {
    case "blocked-input":
      check("check-input", {...input, outcome: "blocked", questions: dispatched});
      break;
    case "before-and-after":
      check("check-input", {...input, outcome: "blocked", questions: dispatched});
      check("private-reply", {...output, outcome: "blocked", candidateAttemptId: "draft",
        checkedText: "I can check someone else’s account.", questions: [questions[2]!]});
      check("permitted-reply", repair);
      break;
    case "mixed-proposal":
      check("check-input", input);
      check("mixed-speech", {...output, outcome: "blocked", candidateAttemptId: "draft", checkedText: draftText,
        questions: [questions[0]!, passed], proposedTools: [{id: "lookup-other", name: "lookup_account"}, {id: "proposed-transfer", name: "transfer"}]});
      check("mixed-transfer", {event: "before_outgoing_transfer", outcome: "blocked", responseTurnId: "turn-1", occurredAt: time(5),
        candidateAttemptId: "draft", transferInvocationId: "proposed-transfer", questions: [
          {...destination, outcome: "failed", probabilityYes: .36, inferredAnswer: "no"}]});
      check("mixed-repair", repair);
      break;
    case "repair-and-transfer":
      check("check-input", input);
      check("check-draft", {...output, outcome: "blocked", candidateAttemptId: "draft", checkedText: draftText, questions: dispatched});
      check("check-repair", repair);
      check("check-transfer", {...transfer, destinationParticipantId: "billing", transferOutcome: "completed"});
      timeline.push({id: transferId, kind: "tool-call", revision: 1, value: {
        id: transferId, toolCallId: transferId, participantId: "routing", activationId: "routing-activation", commandId: "command-1",
        name: "transfer", occurredAt: time(11), status: "completed", request: {destination: "Billing"}, response: {outcome: "Transferred"},
      }});
      break;
    case "transfer-denied":
      check("check-transfer", {...transfer, outcome: "blocked", questions: [
        {...destination, outcome: "failed", probabilityYes: .25, inferredAnswer: "no", feedbackDispatched: true, feedbackOrigin: "fallback",
          feedback: "Failed guardrail: Is billing the correct destination? Required: Yes."}]});
      break;
    case "partial-answer":
      check("check-input", {...input, outcome: "error", errorCode: "partial_answer",
        questions: [{...questions[0]!, feedback: undefined, feedbackOrigin: undefined},
          {...questions[1]!, feedback: undefined, feedbackOrigin: undefined, probabilityYes: undefined, inferredAnswer: undefined, outcome: "unavailable"}],
        attempts: [{id: "partial-request", ordinal: 0, durationMs: 174, model: "gpt-6-luna", outcome: "failed", errorCode: "partial_answer"}]});
      break;
    case "multiple-agents":
      check("check-input", input);
      check("routing-input", {...input, participantId: "routing", outcome: "blocked", questions: dispatched});
      break;
    case "restricted-history":
      message("caller-2", "turn-2", "caller", callerText, 7);
      check("check-input", input);
      check("check-restricted", {sourceParticipantId: "caller", sourceTurnId: "turn-2", occurredAt: time(8),
        contentUnavailable: "denied", outcome: "blocked", questions: []});
      break;
    case "pass":
    case "missing-usage":
      check("check-input", input);
      break;
  }

  const participants = [...snapshot.participants];
  if (checks.some(value => value.participantId === "routing")) {
    const assistant = participants.find(entity => entity.id === "assistant")!;
    participants.push({...assistant, id: "routing", value: {...assistant.value, id: "routing", name: "Routing agent"}});
  }
  const metrics = [...snapshot.metrics];
  if (["repair-and-transfer", "mixed-proposal", "before-and-after"].includes(scenario)) {
    metrics.push({id: "llm-rewrite", revision: 1, value: {label: "Rewrites", value: 1, unit: "requests",
      description: "Conversational model repair dispatch", source: "LLM",
      scope: {kind: "participant-capability", capability: "LLM", participantId: "assistant"}}});
  }
  const details = createCallDetailsStore({...snapshot, timeline, participants, metrics,
    guardrails: checks.map(value => ({id: value.id, revision: 1, value}))});
  return {...base, controller: {details}};
}
