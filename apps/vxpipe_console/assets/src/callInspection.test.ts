import { afterEach, expect, test, vi } from "vitest";

import {
  CallInspectionResponseError,
  createCallInspectionLoader,
  parseCallInspectionResponse,
} from "./callInspection";

afterEach(() => {
  vi.unstubAllGlobals();
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
    "/tenants/tenant%2Fwith%20spaces/calls/call%2Fwith%20spaces/inspection",
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
