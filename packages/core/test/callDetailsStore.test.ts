import { describe, expect, test, vi } from "vitest";
import {
  createCallDetailsController,
  createCallDetailsStore,
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
      durationMs: 3_000,
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
    metricsAvailability: { state: "available" },
    completeness: {
      state: "unconfirmed",
      missingSequenceCount: 0,
      droppedLiveRecords: 0,
    },
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
    expect(store.getSnapshot().metricsAvailability).toEqual({ state: "available" });

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
  test("uses the host-injected endpoint callback to refresh the complete snapshot", async () => {
    const store = createCallDetailsStore(endpointResponse());
    const refreshed = endpointResponse();
    refreshed.completeness = { ...refreshed.completeness, state: "complete" };
    const loader = {
      refresh: vi.fn(async () => refreshed),
    };
    const controller = createCallDetailsController({ store, loader });

    await controller.refresh();
    expect(loader.refresh).toHaveBeenCalledOnce();
    expect(store.getSnapshot().completeness.state).toBe("complete");

    controller.dispose();
  });

  test("replays live updates received while a remote baseline refresh is pending", async () => {
    const store = createCallDetailsStore(endpointResponse());
    let resolveRefresh: (snapshot: CallDetailsSnapshot) => void = () => undefined;
    const loader = {
      refresh: vi.fn(
        async () =>
          new Promise<CallDetailsSnapshot>((resolve) => {
            resolveRefresh = resolve;
          }),
      ),
    };
    const controller = createCallDetailsController({ store, loader });
    const refresh = controller.refresh();

    controller.apply({
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
          text: "Live update during refresh",
          occurredAt: "2026-09-16T08:00:03.000Z",
          state: "final",
        },
      },
    });
    resolveRefresh(endpointResponse());
    await refresh;

    expect(store.getSnapshot().timeline[0]).toMatchObject({
      id: "message-2",
      revision: 2,
      value: { text: "Live update during refresh" },
    });
  });
});
