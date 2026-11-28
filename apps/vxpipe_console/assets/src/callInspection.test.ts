import { afterEach, expect, test, vi } from "vitest";

import {
  CallInspectionResponseError,
  createCallInspectionLoader,
  parseCallInspectionResponse,
} from "./callInspection";

afterEach(() => {
  vi.unstubAllGlobals();
});

test("decodes optional dialogue metadata while preserving literal display text", () => {
  const response = responseFixture("ended");
  const entity = response.timeline[0]!;
  Object.assign(entity.value, { agent_mode: "listener", output_purpose: "backchannel", text: "嗯，okay" });
  const parsed = parseCallInspectionResponse(response);
  expect(parsed.timeline[0]).toMatchObject({ kind: "message", value: {
    text: "嗯，okay", agentMode: "listener", outputPurpose: "backchannel",
  }});
  Object.assign(entity.value, { agent_mode: "invalid" });
  expect(() => parseCallInspectionResponse(response)).toThrow(CallInspectionResponseError);
});

test("retains canonical turn references without inventing them for legacy messages", () => {
  const response = responseFixture("ended");
  expect(parseCallInspectionResponse(response).timeline[0]?.value).not.toHaveProperty("turnId");
  Object.assign(response.timeline[0]!.value, { turn_id: "human-turn-3" });
  expect(parseCallInspectionResponse(response).timeline[0]).toMatchObject({ value: { turnId: "human-turn-3" } });
});

test("preserves both the phone caller ID and the SIP identity", () => {
  const response = responseFixture("ended");
  const caller = response.participants[0]!;
  Object.assign(caller.value, { connection: { kind: "phone", phone_number: "+15550001001", sip_uri: "sip:caller@example.com", caller_id_name: "Example caller" } });
  expect(parseCallInspectionResponse(response).participants[0]?.value.connection).toEqual({kind: "phone", phoneNumber: "+15550001001", sipUri: "sip:caller@example.com", callerIdName: "Example caller"});
});

test("preserves a SIP caller without fabricating a phone number", () => {
  const response = responseFixture("ended");
  Object.assign(response.participants[0]!.value, { connection: {kind: "sip", sip_uri: "sips:caller@example.com", caller_id_name: "+15550001003"} });
  expect(parseCallInspectionResponse(response).participants[0]?.value.connection).toEqual({kind: "sip", sipUri: "sips:caller@example.com", callerIdName: "+15550001003"});
});

test("maps an ongoing database response into the Core snapshot", () => {
  const snapshot = parseCallInspectionResponse(responseFixture("running"));

  expect(snapshot.call).toEqual({
    id: "call-1",
    revision: 3,
    state: "running",
    createdAt: "2026-09-16T09:00:00.000Z",
    startedAt: "2026-09-16T09:00:01.000Z",
    endedAt: null,
    terminalReason: null,
    durationMs: null,
    recording: { status: "not_requested" },
  });
  expect(snapshot.incarnation).toEqual({
    roomId: "room-1",
    incarnationId: "incarnation-1",
  });
  expect(snapshot.participants[0]?.value).toMatchObject({
    id: "caller-1",
    name: "Caller",
    role: "caller",
    connection: { kind: "webrtc" },
    systemPrompt: null,
  });
  expect(snapshot.timeline[0]).toMatchObject({
    kind: "message",
    sourceSequence: 5,
    value: { participantId: "caller-1", occurredAt: "2026-09-16T09:00:05.000Z" },
  });
  expect(snapshot.variables).toEqual({
    state: "available",
    value: {
      revision: 2,
      sections: { order: { revision: 1, value: { status: "ready" } } },
    },
  });
  expect(snapshot.metrics[0]?.value.scope).toEqual({
    kind: "participant-capability",
    participantId: "assistant-1",
    capability: "LLM",
  });
});

test("maps an ended database response without inventing live state", () => {
  const response = responseFixture("ended");
  response.call.ended_at = "2026-09-16T09:01:31.000Z";
  response.call.terminal_reason = "completed";
  response.call.duration_ms = 90_000;

  const snapshot = parseCallInspectionResponse(response);

  expect(snapshot.call).toMatchObject({
    state: "ended",
    endedAt: "2026-09-16T09:01:31.000Z",
    terminalReason: "completed",
    durationMs: 90_000,
  });
  expect(snapshot.completeness).toEqual({
    state: "complete",
    missingSequenceCount: 0,
    droppedLiveRecords: 0,
  });
});

test("fetches the authenticated inspection resource without caching it", async () => {
  const response = responseFixture("running");
  response.call.id = "call/with spaces";
  const fetchMock = vi.fn().mockResolvedValue({
    ok: true,
    json: async () => response,
  });
  vi.stubGlobal("fetch", fetchMock);

  const loader = createCallInspectionLoader("tenant/with spaces", "call/with spaces");
  const snapshot = await loader.refresh(new AbortController().signal);

  expect(snapshot.call.id).toBe("call/with spaces");
  expect(fetchMock).toHaveBeenCalledWith(
    "/api/tenants/tenant%2Fwith%20spaces/calls/call%2Fwith%20spaces/inspection",
    expect.objectContaining({
      credentials: "same-origin",
      cache: "no-store",
      headers: { accept: "application/json" },
    }),
  );
});

test("rejects a response for a different call", async () => {
  vi.stubGlobal(
    "fetch",
    vi.fn().mockResolvedValue({
      ok: true,
      json: async () => responseFixture("running"),
    }),
  );

  await expect(
    createCallInspectionLoader("tenant-1", "call-2").refresh(new AbortController().signal),
  ).rejects.toThrow("different call");
});

test("reports an unavailable inspection response", async () => {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, status: 503 }));

  await expect(
    createCallInspectionLoader("tenant-1", "call-1").refresh(new AbortController().signal),
  ).rejects.toEqual(
    expect.objectContaining<Partial<CallInspectionResponseError>>({
      name: "CallInspectionResponseError",
      status: 503,
    }),
  );
});

test("preserves cancellation while reading the response body", async () => {
  const controller = new AbortController();
  vi.stubGlobal(
    "fetch",
    vi.fn().mockResolvedValue({
      ok: true,
      json: async () => {
        controller.abort();
        throw new DOMException("The operation was aborted.", "AbortError");
      },
    }),
  );

  await expect(
    createCallInspectionLoader("tenant-1", "call-1").refresh(controller.signal),
  ).rejects.toMatchObject({ name: "AbortError" });
});

test("rejects a malformed response at the Console boundary", () => {
  const response = responseFixture("running");
  response.participants[0]!.value.role = "administrator";

  expect(() => parseCallInspectionResponse(response)).toThrow(
    "participants[0].value.role",
  );
});

test("keeps captured null distinct from unavailable collections", () => {
  const response = responseFixture("running");
  const tool = response.timeline[1]!.value as Record<string, unknown>;
  Object.assign(tool, {tool_call_id:"vendor", participant_id:"agent", activation_id:"a", command_id:"cmd"});
  tool.request = null;
  delete tool.response;
  response.variables = { state: "unavailable", reason: "not-captured" } as never;
  response.metrics = [];
  response.metrics_availability = {
    state: "unavailable",
    reason: "not-loaded",
  } as never;

  const snapshot = parseCallInspectionResponse(response);
  const toolCall = snapshot.timeline[1];

  expect(toolCall).toMatchObject({
    kind: "tool-call",
    value: { request: null },
  });
  expect(toolCall?.value).toMatchObject({toolCallId:"vendor", participantId:"agent", activationId:"a", commandId:"cmd"});
  expect(toolCall && "response" in toolCall.value).toBe(false);
  expect(snapshot.variables).toEqual({
    state: "unavailable",
    reason: "not-captured",
  });
  expect(snapshot.metricsAvailability).toEqual({
    state: "unavailable",
    reason: "not-loaded",
  });
});

function responseFixture(state: "running" | "ended") {
  return {
    schema_version: 1,
    call: {
      id: "call-1",
      revision: state === "running" ? 3 : 4,
      state,
      created_at: "2026-09-16T09:00:00.000Z",
      started_at: "2026-09-16T09:00:01.000Z",
      ended_at: null as string | null,
      terminal_reason: null as string | null,
      duration_ms: null as number | null,
    },
    incarnation: { room_id: "room-1", incarnation_id: "incarnation-1" },
    participants: [
      {
        id: "caller-1",
        revision: 1,
        value: {
          id: "caller-1",
          name: "Caller",
          role: "caller",
          state: "listening",
          description: null,
          connection: { kind: "webrtc" },
          capabilities: [{ name: "STT", provider: "morse", model: "morse" }],
          system_prompt: null,
          transfer_policies: [],
          tools: [],
        },
      },
      {
        id: "assistant-1",
        revision: 1,
        value: {
          id: "assistant-1",
          name: "Assistant",
          role: "agent",
          state: "speaking",
          description: "Delivery assistant",
          connection: null,
          capabilities: [{ name: "LLM", provider: "google", model: "gemini" }],
          system_prompt: "Help the caller.",
          transfer_policies: [{ name: "support", description: "" }],
          tools: [{ name: "lookup_order", description: "" }],
        },
      },
    ],
    timeline: [
      {
        id: "message-1",
        revision: 5,
        source_sequence: 5,
        kind: "message",
        value: {
          id: "message-1",
          participant_id: "caller-1",
          text: "I need help",
          occurred_at: "2026-09-16T09:00:05.000Z",
          state: "final",
        },
      },
      {
        id: "tool-1",
        revision: 7,
        source_sequence: 7,
        kind: "tool-call",
        value: {
          id: "tool-1",
          occurred_at: "2026-09-16T09:00:07.000Z",
          name: "lookup_order",
          status: "completed",
          request: {},
          response: { ok: true },
          response_status: 200,
        },
      },
    ],
    variables: {
      state: "available",
      value: {
        revision: 2,
        sections: { order: { revision: 1, value: { status: "ready" } } },
      },
    },
    metrics: [
      {
        id: "metric-1",
        revision: 8,
        value: {
          label: "Input tokens",
          value: 42,
          unit: "tokens",
          source: "google · Provider reported",
          description: "Input tokens",
          scope: {
            kind: "participant-capability",
            participant_id: "assistant-1",
            capability: "LLM",
          },
        },
      },
    ],
    metrics_availability: { state: "available" },
    completeness: {
      state: "complete",
      missing_sequence_count: 0,
      dropped_live_records: 0,
    },
  };
}

test("preserves canonical activity kinds and accepts legacy activities", () => {
  const response = responseFixture("ended");
  const activity = { id: "usage-1", revision: 8, kind: "activity", value: {
    id: "usage-1", occurred_at: "2026-09-16T09:00:08.000Z", text: "Usage observed",
    kind: "call", event_kind: "usage_observed",
  }};
  Object.assign(response, { timeline: [...response.timeline, activity] });
  expect(parseCallInspectionResponse(response).timeline.find((entry) => entry.kind === "activity"))
    .toMatchObject({ value: { eventKind: "usage_observed" } });
  delete (activity.value as Record<string, unknown>).event_kind;
  expect(parseCallInspectionResponse(response).timeline.find((entry) => entry.kind === "activity")?.value)
    .not.toHaveProperty("eventKind");
});

test("defaults a missing call recording to not requested", () => {
  const snapshot = parseCallInspectionResponse(responseFixture("ended"));
  expect(snapshot.call.recording).toEqual({ status: "not_requested" });
});

test("parses recorded and unavailable call recordings", () => {
  const recorded = responseFixture("ended");
  Object.assign(recorded.call, { recording: "recorded" });
  expect(parseCallInspectionResponse(recorded).call.recording).toEqual({ status: "recorded" });

  const unavailable = responseFixture("ended");
  Object.assign(unavailable.call, { recording: "unavailable:storage_unconfigured" });
  expect(parseCallInspectionResponse(unavailable).call.recording).toEqual({
    status: "unavailable",
    reason: "storage_unconfigured",
  });
});

test("parses object-shaped call recordings", () => {
  const response = responseFixture("ended");
  Object.assign(response.call, { recording: { status: "recorded" } });
  expect(parseCallInspectionResponse(response).call.recording).toEqual({ status: "recorded" });
});

test("rejects an invalid call recording", () => {
  const response = responseFixture("ended");
  Object.assign(response.call, { recording: "archived" });
  expect(() => parseCallInspectionResponse(response)).toThrow("call.recording");
});

function guardrailFixture() {
  return {
    id: "gate-1", revision: 7, value: {
      id: "gate-1", participant_id: "assistant-1", occurred_at: "2026-09-16T09:00:06Z",
      event: "after_turn", outcome: "blocked", selected_model: "test-model",
      source_turn_id: "turn-1", candidate_attempt_id: "draft-1", checked_text: "Unsent proposal",
      proposed_tools: [{id: "tool-1", name: "lookup_account"}],
      questions: [{id: "q1", ordinal: 0, question: "Is this their account?", required_answer: "yes",
        threshold_hundredths: 70, outcome: "failed", probability_yes: 0.6999, feedback_origin: "fallback"}],
      attempts: [{id: "attempt-1", ordinal: 0, outcome: "succeeded", duration_ms: 32, input_tokens: 0,
        costs: [{currency: "USD", amount: "0.000000000000100009"}]}],
    },
  };
}

test("parses private guardrail records independently of usage availability", () => {
  const response = responseFixture("running");
  Object.assign(response.metrics[0]!.value, {activation_id: "activation-1", attempt_id: "attempt-1", turn_id: "turn-1"});
  const snapshot = parseCallInspectionResponse({...response, guardrails: [guardrailFixture()],
    metrics_availability: {state: "unavailable", reason: "not-loaded"}});
  expect(snapshot.guardrails).toMatchObject([{id:"gate-1", revision:7, value:{
    sourceTurnId:"turn-1", candidateAttemptId:"draft-1", checkedText:"Unsent proposal",
    proposedTools:[{id:"tool-1",name:"lookup_account"}],
    questions:[{id:"q1",requiredAnswer:"yes",probabilityYes:0.6999,thresholdHundredths:70}],
    attempts:[{id:"attempt-1",durationMs:32,inputTokens:0,costs:[{currency:"USD",amount:"0.000000000000100009"}]}],
  }}]);
  expect(snapshot.guardrails?.[0]?.value.attempts[0]?.totalTokens).toBeUndefined();
  expect(snapshot.metrics[0]?.value).toMatchObject({activationId:"activation-1",attemptId:"attempt-1",turnId:"turn-1"});
});

test("guardrail parsing respects withheld evidence and rejects malformed available records", () => {
  const response = responseFixture("ended");
  const gate = guardrailFixture();
  const parse = (fields: object) => parseCallInspectionResponse({...response,
    guardrails:[{...gate, value:{...gate.value,...fields}}]}).guardrails?.[0]?.value;
  const restricted = parse({content_unavailable:"denied"});
  expect(restricted).toMatchObject({contentUnavailable:"denied", questions:[]});
  expect(restricted?.checkedText).toBeUndefined();
  expect(restricted?.proposedTools).toBeUndefined();
  expect(parse({event:"before_outgoing_transfer", requested_destination:"billing"})?.requestedDestination).toBe("billing");
  expect(parse({content_unavailable:"unknown", requested_destination:"billing"})?.requestedDestination).toBeUndefined();
  expect(parse({actual_model:null})?.actualModel).toBeUndefined();
  expect(() => parse({questions:[{...gate.value.questions[0],probability_yes:2}]})).toThrow(CallInspectionResponseError);
  expect(() => parse({id:"another-evaluation"})).toThrow(CallInspectionResponseError);
  expect(parseCallInspectionResponse(response).guardrails ?? []).toEqual([]);
});
