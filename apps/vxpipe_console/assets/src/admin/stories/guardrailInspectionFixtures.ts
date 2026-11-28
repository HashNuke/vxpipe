// Projected, permission-filtered records for the operator preview.
type QuestionResult = {
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
  transfer?: { id: string; destination: string };
  status: "Passed" | "Blocked" | "Error";
  elapsed: number;
  attempts: { duration: number; outcome: string; tokens: number | null; reportedModel: string | null }[];
  evidence: Evidence | null;
  rewrite?: boolean;
};

export const scenarios = ["blocked-input", "pass", "repair-and-transfer", "transfer-denied", "partial-answer", "restricted-history", "multiple-agents", "missing-usage"] as const;
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
  id: "check-input", event: "Before turn", turn: "turn-1", agent: "assistant", status: "Blocked",
  elapsed: 186, attempts: [answered], evidence: { questions, dispatch: "Feedback sent to model" },
};
const permitted = { questions: [questions[4]] };
const passed: GuardrailCheck = { ...input, status: "Passed", evidence: permitted };
const destination: QuestionResult = {
  id: "q6", question: "Is billing the correct destination?", required: "Yes",
  probability: 0.93, threshold: 0.7, inferred: "Yes", outcome: "Passed",
};
const transfer: GuardrailCheck = {
  ...passed, id: "check-transfer", event: "Before outgoing transfer", turn: null, agent: "routing",
  transfer: { id: "transfer-1", destination: "Billing" }, evidence: { questions: [destination] }, elapsed: 368,
  attempts: [
    { duration: 85, outcome: "Rate limited", tokens: null, reportedModel: null },
    { ...answered, duration: 183, tokens: 86 },
  ],
};

const caller = { turn: "turn-1", participantId: "caller", text: "Can you help me with an account question?" } as const;
const reply = { turn: "turn-2", participantId: "assistant", text: "I can help with your own account." } as const;

export function inspectionFixture(scenario: GuardrailScenario): {
  model: string;
  messages: { turn: Turn; participantId: string; text: string }[];
  checks: GuardrailCheck[];
} {
  const model = "OpenAI · gpt-6-luna";
  switch (scenario) {
    case "blocked-input": return { model, messages: [caller], checks: [input] };
    case "pass": return { model, messages: [caller, reply], checks: [passed] };
    case "repair-and-transfer": return {
      model, messages: [caller, reply], checks: [
        passed,
        { ...input, id: "check-draft", turn: "turn-2", event: "After turn", evidence: {
          questions, dispatch: "Feedback sent · draft withheld", rejectedDraft: "I can look up the other account for you.",
        } },
        { ...passed, id: "check-repair", turn: "turn-2", event: "After turn", rewrite: true,
          evidence: { ...permitted, delivery: "Replacement delivered" } },
        transfer,
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
      model, messages: [caller, { ...caller, turn: "turn-2" }], checks: [
        passed, { ...input, id: "check-restricted", turn: "turn-2", evidence: null },
      ],
    };
  }
}
