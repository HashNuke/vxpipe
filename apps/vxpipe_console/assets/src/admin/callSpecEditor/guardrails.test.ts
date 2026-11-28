import { expect, test } from "vitest";
import { parseSource, serializeSource } from "./source";
import { validateSource } from "./validation";
import { setCapability } from "./edits";
import { renameParticipant } from "./participants";
import { formatThreshold, moveGuardrailQuestion, parseThreshold, passPreview, setGuardrailQuestions } from "./guardrails";

function baseSource(version = "20261128.01") {
  return {
    schema_version: version,
    incoming_call: { caller: "caller", handled_by: "intake" },
    defaults: { capabilities: { decisions: { provider: "openai", model: "gpt-6-luna" } } },
    participants: {
      caller: { type: "human", connection: { service: "web", mode: "receive", admission: "start_call" } },
      intake: {
        type: "agent",
        prompt: "Help the caller with their own account. Ask clarifying questions about their request, confirm the details, and transfer only when asked.",
        transfers: ["scheduling"],
        guardrails: {
          before_turn: [{ question: "Is the caller asking about their own account?", required_answer: "yes" }],
          after_turn: [{ question: "Does this response disclose another patient's details?", required_answer: "no", probability_threshold: 0.75, response: "I can only discuss your own account." }],
          before_outgoing_transfer: [{ question: "Is the requested destination unrelated to the caller's issue?", required_answer: "no" }],
        },
      },
      scheduling: { type: "human", connection: { service: "web", mode: "receive", admission: "transfer" } },
    },
  };
}

test("20261128.01 guardrails round-trip without generated ids", () => {
  const document = parseSource(JSON.stringify(baseSource()));
  expect(document.readOnly).toBe(false);
  expect(validateSource(document.source)).toEqual([]);
});

test("new questions carry no id until the backend assigns one", async () => {
  const document = parseSource(JSON.stringify(baseSource()));
  const next = setGuardrailQuestions(document, "intake", "before_turn", [
    { question: "Is the caller asking about their own account?", required_answer: "yes" },
  ]);
  const saved = next.source.participants.intake as unknown as Record<string, unknown>;
  expect(saved).toHaveProperty("guardrails");
  const event = (saved.guardrails as Record<string, unknown[]>).before_turn[0] as Record<string, unknown>;
  expect(event).not.toHaveProperty("id");
});

test("client validation requires an explicit required answer", async () => {
  const document = parseSource(JSON.stringify(baseSource()));
  const next = setGuardrailQuestions(document, "intake", "before_turn", [{ question: "Is this blocked?" } as never]);
  expect(validateSource(next.source)).toEqual(
    expect.arrayContaining([expect.objectContaining({ path: ["participants", "intake", "guardrails", "before_turn", "0", "required_answer"] })]),
  );
});

test("threshold helpers use the P(Yes) scale with a 0.70 default", () => {
  expect(formatThreshold(undefined)).toBe("");
  expect(formatThreshold(0.7)).toBe("0.70");
  expect(parseThreshold("")).toBeUndefined();
  expect(parseThreshold("0.75")).toBe(0.75);
  expect(parseThreshold("0.7")).toBe(0.7);
  expect(parseThreshold("1.00")).toBe(1);
  expect(parseThreshold("0.777")).toBeNull();
  expect(parseThreshold("yes")).toBeNull();
  expect(passPreview(undefined, "yes")).toBe("Passes when P(Yes) ≥ 0.70");
  expect(passPreview(0.75, "no")).toBe("Passes when P(Yes) < 0.75");
  expect(passPreview(0, "yes")).toBe("Always passes: P(Yes) ≥ 0.00 always holds, so Yes is always inferred.");
  expect(passPreview(0, "no")).toBe("Always fails: P(Yes) ≥ 0.00 always holds, so Yes is always inferred.");
  expect(passPreview(0, undefined)).toBe("Choose Yes or No to preview when this passes.");
  expect(passPreview(undefined, undefined)).toBe("Choose Yes or No to preview when this passes.");
  expect(passPreview(0.75, undefined)).toBe("Choose Yes or No to preview when this passes.");
  expect(passPreview(1, undefined)).toBe("Choose Yes or No to preview when this passes.");
  expect(passPreview(1, "yes")).toBe("Passes only when P(Yes) = 1.00.");
});

test("reorder keeps backend-assigned ids stable", async () => {
  const document = parseSource(JSON.stringify(baseSource()));
  const questions = moveGuardrailQuestion([
    { id: "first_question", question: "First?", required_answer: "yes" },
    { id: "second_question", question: "Second?", required_answer: "no" },
  ], 0, 1);
  const moved = setGuardrailQuestions(document, "intake", "before_turn", questions);
  expect(questions.map((entry) => entry.id)).toEqual(["second_question", "first_question"]);
  expect(validateSource(moved.source)).toEqual([]);
});

test("participant rename preserves guardrail questions", () => {
  const document = parseSource(JSON.stringify(baseSource()));
  const renamed = renameParticipant(document, "intake", "reception");
  const guardrails = (renamed.source.participants.reception as unknown as { guardrails: object }).guardrails;
  expect(guardrails).toMatchObject({ before_turn: [{ required_answer: "yes" }], after_turn: [{ required_answer: "no" }] });
  expect(renamed.source.participants.intake).toBeUndefined();
  expect(validateSource(renamed.source)).toEqual([]);
});

test("guardrails survive JSON serialization without generated ids", () => {
  const document = parseSource(JSON.stringify(baseSource()));
  const roundTripped = parseSource(serializeSource(document));
  expect(roundTripped.source).toEqual(document.source);
});

test("schema versions keep old revisions read-only without rewriting", () => {
  const current = parseSource(JSON.stringify(baseSource("20261128.01")));
  expect(current.readOnly).toBe(false);
  const retained = parseSource(JSON.stringify(baseSource("20261125.01")));
  expect(retained.readOnly).toBe(false);
  expect(JSON.parse(serializeSource(retained))).toMatchObject({ schema_version: "20261125.01" });
  const historical = parseSource(JSON.stringify(baseSource("20261004.01")));
  expect(historical.readOnly).toBe(true);
  expect(() => parseSource(JSON.stringify(baseSource("20990101.01")))).toThrow();
});

test("empty question lists need no Decisions model", () => {
  const source = baseSource();
  delete (source.participants.intake as Record<string, unknown>).guardrails;
  delete (source.defaults as Record<string, unknown>).capabilities;
  const document = parseSource(JSON.stringify(source));
  expect(validateSource(document.source)).toEqual([]);
});

test("questions without a Decisions model are flagged on the call settings", () => {
  const source = baseSource();
  delete (source.defaults as Record<string, unknown>).capabilities;
  const document = parseSource(JSON.stringify(source));
  expect(validateSource(document.source)).toEqual(
    expect.arrayContaining([expect.objectContaining({ path: ["defaults", "capabilities", "decisions"] })]),
  );
});

test("per-agent Decisions overrides are rejected", () => {
  const source = baseSource();
  (source.participants.intake as Record<string, unknown>).capabilities = { decisions: { provider: "openai", model: "gpt-6-luna" } };
  const document = parseSource(JSON.stringify(source));
  expect(validateSource(document.source)).toEqual(
    expect.arrayContaining([expect.objectContaining({ path: ["participants", "intake", "capabilities", "decisions"] })]),
  );
});

test("turn checks are rejected for speech-to-speech agents", () => {
  const source = baseSource();
  (source.participants.intake as Record<string, unknown>).capabilities = { speech_to_speech: { provider: "openai", model: "gpt-live-1" } };
  const document = parseSource(JSON.stringify(source));
  const issues = validateSource(document.source);
  expect(issues).toEqual(expect.arrayContaining([
    expect.objectContaining({ path: ["participants", "intake", "guardrails", "before_turn"] }),
    expect.objectContaining({ path: ["participants", "intake", "guardrails", "after_turn"] }),
  ]));
  expect(issues.some((issue) => issue.path.join(".") === "participants.intake.guardrails.before_outgoing_transfer")).toBe(false);
});

test("malformed thresholds, ids and responses are rejected with field paths", () => {
  const source = baseSource("20261128.01");
  const guardrails = (source.participants.intake as unknown as { guardrails: { before_turn: Record<string, unknown>[] } }).guardrails;
  guardrails.before_turn = [
    { id: "Bad Id", question: "", required_answer: "maybe", probability_threshold: "high", response: 42 },
    { id: "ok_id", question: "Fine?", required_answer: "yes", probability_threshold: 0.777 },
  ];
  const document = parseSource(JSON.stringify(source));
  const paths = validateSource(document.source).map((issue) => issue.path.join("."));
  expect(paths).toEqual(expect.arrayContaining([
    "participants.intake.guardrails.before_turn.0.id",
    "participants.intake.guardrails.before_turn.0.question",
    "participants.intake.guardrails.before_turn.0.required_answer",
    "participants.intake.guardrails.before_turn.0.probability_threshold",
    "participants.intake.guardrails.before_turn.0.response",
    "participants.intake.guardrails.before_turn.1.probability_threshold",
  ]));
});

test("guardrails need the new schema version", () => {
  const document = parseSource(JSON.stringify(baseSource("20261125.01")));
  expect(validateSource(document.source)).toEqual(
    expect.arrayContaining([expect.objectContaining({ path: ["participants", "intake", "guardrails"] })]),
  );
});

test("question lists are bounded", () => {
  const source = baseSource();
  const guardrails = (source.participants.intake as unknown as { guardrails: { before_turn: Record<string, unknown>[] } }).guardrails;
  guardrails.before_turn = Array.from({ length: 33 }, (_, index) => ({ question: `Question ${index}?`, required_answer: "yes" }));
  const document = parseSource(JSON.stringify(source));
  expect(validateSource(document.source)).toEqual(
    expect.arrayContaining([expect.objectContaining({ path: ["participants", "intake", "guardrails", "before_turn"] })]),
  );
});

test("adding guardrails to a retained editable revision upgrades only the new draft", () => {
  const source = baseSource("20261125.01");
  delete (source.participants.intake as Record<string, unknown>).guardrails;
  delete (source.defaults as Record<string, unknown>).capabilities;
  const retained = parseSource(JSON.stringify(source));
  const selected = setCapability(retained, null, "decisions", { provider: "openai", model: "gpt-6-luna" });
  const questions = [{ question: "Is this in scope?", required_answer: "yes" as const }];
  const edited = setGuardrailQuestions(retained, "intake", "before_turn", questions);
  expect(selected.source.schema_version).toBe("20261128.01");
  expect(edited.source.schema_version).toBe("20261128.01");
  expect(validateSource(setGuardrailQuestions(selected, "intake", "before_turn", questions).source)).toEqual([]);
  expect(retained.source).toEqual(source);
});
