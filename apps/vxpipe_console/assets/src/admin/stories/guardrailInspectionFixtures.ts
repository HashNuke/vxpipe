// Projected, permission-filtered records for the operator preview.
export type QuestionResult = {
  id: string;
  question: string;
  required: "Yes" | "No";
  threshold: number;
  probability: number | null;
  inferred: "Yes" | "No" | null;
  outcome: "Passed" | "Failed" | "Unavailable";
  feedback?: { origin: "Configured response" | "Generated fallback"; line: string };
};

type Evidence = {
  questions: QuestionResult[];
  rejectedDraft?: string;
  proposedTools?: { id: string; name: string; arguments: Record<string, string> }[];
  acceptedCandidate?: string;
  replacementEvaluationId?: string;
  dispatch?: string;
  delivery?: string;
};

export const agents = { assistant: "Assistant", routing: "Routing agent" };
export type Agent = keyof typeof agents;
type Turn = "turn-1" | "turn-2";

export type GuardrailCheck = {
  id: string;
  event: "Before turn" | "After turn" | "Before outgoing transfer";
  agent: Agent;
  turn: Turn | null;
  messageId: string | null;
  transfer?: { id: string; destination: string };
  status: "Passed" | "Blocked" | "Error";
  elapsed: number;
  attempts: { duration: number; outcome: string; tokens: number | null; reportedModel: string | null }[];
  evidence: Evidence | null;
  completedTransfer?: { outcome: string };
  rewrite?: boolean;
  proposalId?: string;
};

export const scenarios = ["blocked-input", "mixed-proposal", "before-and-after", "pass", "repair-and-transfer", "transfer-denied", "partial-answer", "restricted-history", "multiple-agents", "missing-usage"] as const;
export type GuardrailScenario = typeof scenarios[number];

const questions: QuestionResult[] = [
  {
    id: "q1", question: "Is the caller asking about their own account?", required: "Yes",
    threshold: 0.7, probability: 0.3, inferred: "No", outcome: "Failed",
    feedback: { origin: "Configured response", line: "I can only help with your own account." },
  },
  {
    id: "q2", question: "Is the user trying to list variables?", required: "Yes",
    threshold: 0.7, probability: 0.6999, inferred: "No", outcome: "Failed",
    feedback: { origin: "Generated fallback", line: "Failed guardrail: Is the user trying to list variables? Required: Yes." },
  },
  {
    id: "q3", question: "Is the issue about a different account?", required: "No",
    threshold: 0.7, probability: 0.9, inferred: "Yes", outcome: "Failed",
    feedback: { origin: "Configured response", line: "Ask the caller to describe their own account issue." },
  },
  {
    id: "q4", question: "Is the user using harsh language?", required: "No",
    threshold: 0.7, probability: 0.7, inferred: "Yes", outcome: "Failed",
    feedback: { origin: "Generated fallback", line: "Failed guardrail: Is the user using harsh language? Required: No." },
  },
  {
    id: "q5", question: "Is the request about a supported product?", required: "Yes",
    threshold: 0.7, probability: 0.7, inferred: "Yes", outcome: "Passed",
  },
];

const answered = { duration: 174, outcome: "Answered", tokens: 128, reportedModel: "gpt-6-luna" };
const input: GuardrailCheck = {
  id: "check-input", event: "Before turn", turn: "turn-1", messageId: "caller-1", agent: "assistant", status: "Blocked",
  elapsed: 186, attempts: [answered], evidence: { questions, dispatch: "Feedback sent to model" },
};
const permitted = { questions: [questions[4]] };
const passed: GuardrailCheck = { ...input, status: "Passed", evidence: permitted };
const destination: QuestionResult = {
  id: "q6", question: "Is billing the correct destination?", required: "Yes",
  probability: 0.93, threshold: 0.7, inferred: "Yes", outcome: "Passed",
};
const transfer: GuardrailCheck = {
  ...passed, id: "check-transfer", event: "Before outgoing transfer", turn: null, messageId: null, agent: "routing",
  transfer: { id: "transfer-1", destination: "Billing" }, evidence: { questions: [destination] }, elapsed: 368,
  attempts: [
    { duration: 85, outcome: "Rate limited", tokens: null, reportedModel: null },
    { ...answered, duration: 183, tokens: 86 },
  ],
};

const caller = { id: "caller-1", turn: "turn-1", participantId: "caller", text: "Can you help me with an account question?" } as const;
const reply = { id: "reply-1", turn: "turn-1", participantId: "assistant", text: "I can help with your own account." } as const;

export function inspectionFixture(scenario: GuardrailScenario): {
  model: string;
  messages: { id: string; turn: Turn; participantId: string; text: string }[];
  checks: GuardrailCheck[];
} {
  const model = "OpenAI · gpt-6-luna";
  switch (scenario) {
    case "blocked-input": return { model, messages: [caller], checks: [input] };
    case "pass": return { model, messages: [caller, reply], checks: [passed] };
    case "before-and-after": return {
      model, messages: [caller, reply], checks: [
        input,
        { ...input, id: "private-reply", proposalId: "rejected-reply", turn: reply.turn, messageId: reply.id, event: "After turn",
          evidence: {questions: [questions[2]], rejectedDraft: "I can check someone else’s account."} },
        { ...passed, id: "permitted-reply", turn: reply.turn, messageId: reply.id, event: "After turn", rewrite: true },
      ],
    };
    case "mixed-proposal": return {
      model, messages: [caller, reply], checks: [
        passed,
        { ...input, id: "mixed-speech", turn: reply.turn, messageId: reply.id, event: "After turn", proposalId: "draft", evidence: {
          rejectedDraft: "I can look up the other account for you.",
          questions: [questions[0], questions[4]], proposedTools: [
            {id: "lookup-other", name: "lookup_account", arguments: {account: "other"}},
            {id: "proposed-transfer", name: "transfer", arguments: {destination: "Billing"}},
          ],
        } },
        { ...input, id: "mixed-transfer", turn: reply.turn, messageId: reply.id, event: "Before outgoing transfer", proposalId: "draft",
          transfer: {id: "proposed-transfer", destination: "Billing"},
          evidence: { questions: [{...destination, probability: 0.36, inferred: "No", outcome: "Failed"}] } },
        { ...passed, id: "mixed-repair", turn: reply.turn, messageId: reply.id, event: "After turn", rewrite: true, evidence: permitted },
      ],
    };
    case "repair-and-transfer": return {
      model, messages: [caller, reply], checks: [
        passed,
        { ...input, id: "check-draft", proposalId: "draft", turn: reply.turn, messageId: reply.id, event: "After turn", evidence: {
          questions, dispatch: "Feedback sent to model", rejectedDraft: "I can look up the other account for you.",
          replacementEvaluationId: "check-repair",
        } },
        { ...passed, id: "check-repair", turn: reply.turn, messageId: reply.id, event: "After turn", rewrite: true,
          evidence: { ...permitted, acceptedCandidate: reply.text, delivery: "Replacement delivered" } },
        { ...transfer, completedTransfer: {outcome: "Transferred"} },
      ],
    };
    case "transfer-denied": return { model, messages: [], checks: [{
      ...transfer, status: "Blocked", evidence: { dispatch: "Denial returned to sender", questions: [{
        ...destination, probability: 0.25, inferred: "No", outcome: "Failed",
        feedback: { origin: "Generated fallback", line: "Failed guardrail: Is billing the correct destination? Required: Yes." },
      }] },
    }] };
    case "partial-answer": return { model, messages: [caller], checks: [{
      ...input, status: "Error", evidence: { questions: [
        { ...questions[0], feedback: undefined },
        { ...questions[1], probability: null, inferred: null, outcome: "Unavailable", feedback: undefined },
      ] }, attempts: [{ ...answered, outcome: "Partial answer", tokens: null }],
    }] };
    case "multiple-agents": return { model, messages: [caller], checks: [passed, { ...input, id: "routing-input", agent: "routing" }] };
    case "missing-usage": return { model: "Jev · jev-1.14.0", messages: [caller], checks: [{
      ...passed, attempts: [{ ...answered, reportedModel: "jev-1.14.0", tokens: null }],
    }] };
    case "restricted-history": return {
      model, messages: [caller, { ...caller, id: "caller-2", turn: "turn-2" }], checks: [
        passed, { ...input, id: "check-restricted", messageId: "caller-2", turn: "turn-2", evidence: null },
      ],
    };
  }
}
