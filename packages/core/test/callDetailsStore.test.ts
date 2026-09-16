import { describe, expect, test, vi } from "vitest";
import {
  createCallDetailsController,
  createCallDetailsStore,
  type CallDetailsPage,
  type CallDetailsSnapshot,
  type CallDetailsUpdate,
} from "../src/index.js";

function endpointResponse(): CallDetailsSnapshot {
  return {
    schemaVersion: 1,
    call: {
      id: "call-001",
      revision: 1,
      state: "running",
      createdAt: "2026-09-16T08:00:00.000Z",
      startedAt: "2026-09-16T08:00:01.000Z",
      endedAt: null,
      terminalReason: null,
    },
    incarnation: { roomId: "room-001", incarnationId: "inc-001" },
    participants: [
      {
        id: "assistant",
        revision: 1,
        value: {
          id: "assistant",
          name: "Assistant",
          role: "agent",
          state: "speaking",
          description: null,
          capabilities: [],
          systemPrompt: null,
          transferPolicies: [],
          tools: [],
        },
      },
    ],
    timeline: [
      {
        id: "message-2",
        revision: 1,
        sourceSequence: 2,
        kind: "message",
        value: {
          id: "message-2",
          participantId: "assistant",
          text: "Working on it",
          occurredAt: "2026-09-16T08:00:03.000Z",
          state: "streaming",
        },
      },
      {
        id: "rtvi-receipt-1",
        revision: 1,
        sourceSequence: 3,
        kind: "protocol-event",
        value: {
          id: "rtvi-receipt-1",
          protocol: "rtvi",
          type: "bot-output",
          direction: "in",
          occurredAt: "2026-09-16T08:00:03.010Z",
          summary: "Agent text fragment",
          details: { text: "Working on it" },
        },
      },
    ],
    variables: {
      state: "available",
      value: { revision: 1, sections: {} },
    },
    metrics: [],
    completeness: {
      state: "unconfirmed",
      missingSequenceCount: 0,
      droppedLiveRecords: 0,
    },
    olderCursor: "older-1",
    asOf: "2026-09-16T08:00:04.000Z",
  };
}

describe("call details store", () => {
  test("hydrates a mock endpoint response and applies only newer semantic revisions", () => {
    const store = createCallDetailsStore(endpointResponse());
    const initial = store.getSnapshot();

    const finalMessage: CallDetailsUpdate = {
      type: "timeline-upsert",
      callId: "call-001",
      incarnationId: "inc-001",
      entity: {
        id: "message-2",
        revision: 2,
        sourceSequence: 2,
        kind: "message",
        value: {
          id: "message-2",
          participantId: "assistant",
          text: "Working on it now",
          occurredAt: "2026-09-16T08:00:03.000Z",
          state: "final",
        },
      },
    };

    expect(store.apply(finalMessage)).toBe(true);
    expect(store.getSnapshot()).not.toBe(initial);
    expect(store.getSnapshot().timeline[0]).toMatchObject({
      id: "message-2",
      revision: 2,
      value: { text: "Working on it now", state: "final" },
    });

    const current = store.getSnapshot();
    expect(
      store.apply({
        ...finalMessage,
        entity: { ...finalMessage.entity, revision: 1 },
      }),
    ).toBe(false);
    expect(store.getSnapshot()).toBe(current);
  });

  test("keeps raw RTVI receipts append-only while semantic events can update", () => {
    const store = createCallDetailsStore(endpointResponse());

    expect(
      store.apply({
        type: "timeline-upsert",
        callId: "call-001",
        incarnationId: "inc-001",
        entity: {
          id: "rtvi-receipt-2",
          revision: 1,
          sourceSequence: 4,
          kind: "protocol-event",
          value: {
            id: "rtvi-receipt-2",
            protocol: "rtvi",
            type: "bot-output",
            direction: "in",
            occurredAt: "2026-09-16T08:00:03.020Z",
            summary: "Corrected agent text",
            details: { text: "Working on it now" },
          },
        },
      }),
    ).toBe(true);

    expect(
      store
        .getSnapshot()
        .timeline.filter((item) => item.kind === "protocol-event"),
    ).toHaveLength(2);

    const snapshot = store.getSnapshot();
    expect(
      store.apply({
        type: "timeline-upsert",
        callId: "call-001",
        incarnationId: "inc-001",
        entity: {
          ...snapshot.timeline.find((item) => item.id === "rtvi-receipt-1")!,
          revision: 2,
        },
      }),
    ).toBe(false);
    expect(store.getSnapshot()).toBe(snapshot);
  });

  test("merges overlapping endpoint pages and orders timeline items deterministically", () => {
    const store = createCallDetailsStore(endpointResponse());
    const page: CallDetailsPage = {
      callId: "call-001",
      timeline: [
        endpointResponse().timeline[0]!,
        {
          id: "message-1",
          revision: 1,
          sourceSequence: 1,
          kind: "message",
          value: {
            id: "message-1",
            participantId: "assistant",
            text: "Hello",
            occurredAt: "2026-09-16T08:00:02.000Z",
            state: "final",
          },
        },
      ],
      olderCursor: null,
    };

    expect(store.mergePage(page)).toBe(true);
    expect(store.getSnapshot().timeline.map((item) => item.id)).toEqual([
      "message-1",
      "message-2",
      "rtvi-receipt-1",
    ]);
    expect(store.getSnapshot().olderCursor).toBeNull();
  });

  test("rejects stale incarnations and supports explicit tombstones", () => {
    const store = createCallDetailsStore(endpointResponse());
    expect(
      store.apply({
        type: "timeline-remove",
        callId: "call-001",
        incarnationId: "inc-old",
        id: "message-2",
        revision: 2,
      }),
    ).toBe(false);
    expect(store.getSnapshot().timeline.some((item) => item.id === "message-2")).toBe(true);

    expect(
      store.apply({
        type: "timeline-remove",
        callId: "call-001",
        incarnationId: "inc-001",
        id: "message-2",
        revision: 2,
      }),
    ).toBe(true);
    expect(store.getSnapshot().timeline.some((item) => item.id === "message-2")).toBe(false);
  });
});

describe("call details controller", () => {
  test("uses host-injected endpoint callbacks for refresh and pagination", async () => {
    const store = createCallDetailsStore(endpointResponse());
    const refreshed = endpointResponse();
    refreshed.asOf = "2026-09-16T08:01:00.000Z";
    refreshed.completeness = { ...refreshed.completeness, state: "complete" };
    const page: CallDetailsPage = {
      callId: "call-001",
      timeline: [],
      olderCursor: null,
    };
    const loader = {
      refresh: vi.fn(async () => refreshed),
      loadOlder: vi.fn(async () => page),
    };
    const controller = createCallDetailsController({ store, loader });

    await controller.refresh();
    expect(loader.refresh).toHaveBeenCalledOnce();
    expect(store.getSnapshot().asOf).toBe("2026-09-16T08:01:00.000Z");

    await controller.loadOlder();
    expect(loader.loadOlder).toHaveBeenCalledWith("older-1", expect.any(AbortSignal));
    expect(store.getSnapshot().olderCursor).toBeNull();

    controller.dispose();
  });
});
