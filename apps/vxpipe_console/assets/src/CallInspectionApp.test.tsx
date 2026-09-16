import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, expect, test, vi } from "vitest";
import type {
  CallConsoleController,
  CallDetailsLoader,
  CallDetailsSnapshot,
} from "@vxpipe/core";

vi.mock("@vxpipe/react", () => ({
  CallConsole: ({ controller }: { controller: CallConsoleController }) => {
    const details = controller.details.getSnapshot();
    const message = details.timeline.find((entity) => entity.kind === "message");
    return (
      <main>
        <p>{details.call.state === "ended" ? "Call ended" : "In progress"}</p>
        <p>{message?.value.text}</p>
      </main>
    );
  },
}));

import { CallInspectionApp } from "./CallInspectionApp";

afterEach(cleanup);

test.each([
  ["running", "In progress"],
  ["ended", "Call ended"],
] as const)("renders a remote %s call through the reusable console", async (state, status) => {
  const loader: CallDetailsLoader = {
    refresh: vi.fn(async () => snapshot(state)),
  };

  render(<CallInspectionApp tenantKey="tenant-1" callId="call-1" loader={loader} />);

  expect(await screen.findByText("Loaded from call history")).toBeVisible();
  expect(screen.getByText(status)).toBeVisible();
  expect(screen.queryByRole("button", { name: "Start call" })).not.toBeInTheDocument();
  expect(loader.refresh).toHaveBeenCalledOnce();
});

test("shows an inspection error without rendering stale console state", async () => {
  const loader: CallDetailsLoader = {
    refresh: vi.fn(async () => {
      throw new Error("Call inspection returned malformed JSON.");
    }),
  };

  render(<CallInspectionApp tenantKey="tenant-1" callId="call-1" loader={loader} />);

  expect(await screen.findByRole("alert")).toHaveTextContent(
    "Call inspection returned malformed JSON.",
  );
  expect(screen.queryByText("Loaded from call history")).not.toBeInTheDocument();
});

function snapshot(state: "running" | "ended"): CallDetailsSnapshot {
  return {
    schemaVersion: 1,
    call: {
      id: "call-1",
      revision: state === "running" ? 3 : 4,
      state,
      createdAt: "2026-09-16T08:00:00.000Z",
      startedAt: "2026-09-16T08:00:01.000Z",
      endedAt: state === "ended" ? "2026-09-16T08:02:15.000Z" : null,
      terminalReason: state === "ended" ? "completed" : null,
      durationMs: state === "ended" ? 134_000 : null,
    },
    incarnation: { roomId: "room-1", incarnationId: "incarnation-1" },
    participants: [
      {
        id: "assistant-1",
        revision: 1,
        value: {
          id: "assistant-1",
          name: "Assistant",
          role: "agent",
          state: state === "ended" ? "left" : "listening",
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
        id: "message-1",
        revision: 1,
        sourceSequence: 1,
        kind: "message",
        value: {
          id: "message-1",
          participantId: "assistant-1",
          text: "Loaded from call history",
          occurredAt: "2026-09-16T08:00:02.000Z",
          state: "final",
        },
      },
    ],
    variables: { state: "unavailable", reason: "not-captured" },
    metrics: [],
    metricsAvailability: { state: "unavailable", reason: "not-loaded" },
    completeness: {
      state: "complete",
      missingSequenceCount: 0,
      droppedLiveRecords: 0,
    },
  };
}
