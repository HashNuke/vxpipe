import { render, screen } from "@testing-library/react";
import { expect, test, vi } from "vitest";
import {
  createCallDetailsController,
  createCallDetailsStore,
  type CallConsoleController,
  type CallDetailsSnapshot,
} from "@vxpipe/core";
import { CallConsole } from "../src/index.js";

function mockEndpointResponse(
  state: CallDetailsSnapshot["call"]["state"] = "ended",
): CallDetailsSnapshot {
  return {
    schemaVersion: 1,
    call: {
      id: "remote-call-001",
      revision: 1,
      state,
      createdAt: "2026-09-16T08:00:00.000Z",
      startedAt: "2026-09-16T08:00:01.000Z",
      endedAt: state === "ended" ? "2026-09-16T08:02:15.000Z" : null,
      terminalReason: null,
      durationMs: 134_000,
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
        id: "remote-message-1",
        revision: 1,
        sourceSequence: 1,
        kind: "message",
        value: {
          id: "remote-message-1",
          participantId: "assistant",
          text: "Loaded from call history",
          occurredAt: "2026-09-16T08:00:02.000Z",
          state: "final",
        },
      },
    ],
    variables: { state: "unavailable", reason: "not-captured" },
    metrics: [],
    completeness: {
      state: "complete",
      missingSequenceCount: 0,
      droppedLiveRecords: 0,
    },
    olderCursor: null,
    asOf: "2026-09-16T08:02:15.000Z",
  };
}

test("renders an ended call from a mocked endpoint response without live controls", () => {
  const details = createCallDetailsStore(mockEndpointResponse());
  const controller: CallConsoleController = { details };

  render(<CallConsole controller={controller} />);

  expect(screen.getByText("Loaded from call history")).toBeVisible();
  expect(screen.getByText("Call ended")).toBeVisible();
  expect(screen.queryByRole("button", { name: "Call" })).not.toBeInTheDocument();
  expect(screen.queryByRole("group", { name: "Input audio" })).not.toBeInTheDocument();
  expect(screen.queryByRole("textbox", { name: "Message" })).not.toBeInTheDocument();
});

test("renders an ongoing remote call without joining its RTVI session", () => {
  const store = createCallDetailsStore(mockEndpointResponse("running"));
  const history = createCallDetailsController({
    store,
    loader: {
      refresh: vi.fn(async () => mockEndpointResponse("running")),
      loadOlder: vi.fn(),
    },
  });
  const controller: CallConsoleController = { details: history, history };

  render(<CallConsole controller={controller} />);

  expect(screen.getByText("Loaded from call history")).toBeVisible();
  expect(screen.getByText("In progress")).toBeVisible();
  expect(screen.queryByRole("button", { name: "Leave call" })).not.toBeInTheDocument();
});
