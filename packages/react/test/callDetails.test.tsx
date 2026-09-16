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
    metricsAvailability: { state: "unavailable", reason: "not-loaded" },
    completeness: {
      state: "complete",
      missingSequenceCount: 0,
      droppedLiveRecords: 0,
    },
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
  const response = mockEndpointResponse("running");
  response.call.durationMs = null;
  const store = createCallDetailsStore(response);
  const history = createCallDetailsController({
    store,
    loader: {
      refresh: vi.fn(async () => mockEndpointResponse("running")),
    },
  });
  const controller: CallConsoleController = { details: history, history };

  render(<CallConsole controller={controller} />);

  expect(screen.getByText("Loaded from call history")).toBeVisible();
  expect(screen.getByText("In progress")).toBeVisible();
  expect(screen.getByText("—")).toBeVisible();
  expect(screen.queryByText("00:00")).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Leave call" })).not.toBeInTheDocument();
});

test("distinguishes unavailable metrics from an available empty report", () => {
  const unavailable = createCallDetailsStore(mockEndpointResponse());
  const { unmount } = render(
    <CallConsole controller={{ details: unavailable }} initialTab="metrics" />,
  );

  expect(screen.getByText("Metrics unavailable.")).toBeVisible();
  unmount();

  const emptyResponse = mockEndpointResponse();
  emptyResponse.metricsAvailability = { state: "available" };
  const empty = createCallDetailsStore(emptyResponse);
  render(<CallConsole controller={{ details: empty }} initialTab="metrics" />);

  expect(screen.getByText("No metrics recorded.")).toBeVisible();
});

test("preserves repeated metric observations for the same target and label", () => {
  const response = mockEndpointResponse();
  response.metricsAvailability = { state: "available" };
  response.metrics = [10, 20].map((value, index) => ({
    id: `attempt-${index + 1}`,
    revision: index + 1,
    value: {
      label: "Input tokens",
      value,
      unit: "tokens",
      source: `LLM provider · attempt ${index + 1}`,
      description: "Provider-reported input tokens",
      scope: {
        kind: "participant-capability" as const,
        participantId: "assistant",
        capability: "LLM",
      },
    },
  }));

  const details = createCallDetailsStore(response);
  render(<CallConsole controller={{ details }} initialTab="metrics" />);

  expect(
    screen.getByRole("button", { name: "Input tokens for LLM, Assistant: 10 tokens" }),
  ).toBeVisible();
  expect(
    screen.getByRole("button", { name: "Input tokens for LLM, Assistant: 20 tokens" }),
  ).toBeVisible();
});
