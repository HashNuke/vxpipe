import { fireEvent, render, screen } from "@testing-library/react";
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

test("labels a listening cue without changing participant media state", () => {
  const response = mockEndpointResponse();
  const entity = response.timeline[0]!;
  if (entity.kind !== "message") throw new Error("fixture message missing");
  Object.assign(entity.value, { text: "嗯，okay", agentMode: "listener", outputPurpose: "backchannel", spokenRange: { start: 0, end: 2 } });
  const details = createCallDetailsStore(response);
  render(<CallConsole controller={{ details }} />);
  expect(screen.getByRole("article")).toHaveTextContent("嗯，okay");
  expect(screen.getByText("Backchannel")).toBeVisible();
  expect(document.querySelector("mark")?.textContent).toBe("嗯，");
  expect(details.getSnapshot().participants[0]?.value.state).toBe("left");
});

test("keeps JSON-looking human speech literal and does not label input mode as a cue", () => {
  const response = mockEndpointResponse();
  const entity = response.timeline[0]!;
  if (entity.kind !== "message") throw new Error("fixture message missing");
  Object.assign(entity.value, { text: '{"message":"literal"}', agentMode: "listener" });
  render(<CallConsole controller={{ details: createCallDetailsStore(response) }} />);
  expect(screen.getByText('{"message":"literal"}')).toBeVisible();
  expect(screen.queryByText("Backchannel")).not.toBeInTheDocument();
});

test("does not render empty dialogue as a speech bubble", () => {
  const response = mockEndpointResponse();
  const entity = response.timeline[0]!;
  if (entity.kind !== "message") throw new Error("fixture message missing");
  entity.value.text = " \n";
  render(<CallConsole controller={{ details: createCallDetailsStore(response) }} />);
  expect(screen.queryAllByRole("article")).toHaveLength(0);
  expect(screen.getByText("No call active")).toBeVisible();
});

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

  expect(screen.getByRole("group", { name: "Input tokens summary for LLM, Assistant" })).toHaveTextContent("Total30");
  fireEvent.click(screen.getByRole("button", { name: "Expand metrics for LLM, Assistant" }));
  expect(
    screen.getByRole("button", { name: "Input tokens for LLM, Assistant: 10 tokens" }),
  ).toBeVisible();
  expect(
    screen.getByRole("button", { name: "Input tokens for LLM, Assistant: 20 tokens" }),
  ).toBeVisible();
});

const technicalKinds = [
  "usage_observed", "agent_output_delivery_progressed", "agent_output_delivered",
  "agent_output_delivery_started", "participant_transcription_final",
  "participant_turn_started", "agent_turn_completed",
];

test("technical archive facts are opt-in without hiding conversation or losing stored evidence", () => {
  const response = mockEndpointResponse();
  const kinds = [...technicalKinds, "agent_turn_failed", "agent_turn_interrupted", "future_event"];
  response.timeline = [...response.timeline, ...kinds.map((eventKind, index) => ({
    id: eventKind, revision: 1, sourceSequence: index + 2, kind: "activity" as const,
    value: { id: eventKind, occurredAt: "2026-09-16T08:00:03.000Z", text: eventKind,
      kind: "call" as const, eventKind },
  }))];
  const details = createCallDetailsStore(response);
  render(<CallConsole controller={{ details }} />);
  for (const kind of technicalKinds) expect(screen.queryByText(kind)).not.toBeInTheDocument();
  for (const kind of kinds.slice(7)) expect(screen.getByText(kind)).toBeVisible();
  expect(screen.getByText("Loaded from call history")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Show Technical events" }));
  for (const kind of technicalKinds) expect(screen.getByText(kind)).toBeVisible();
  const shown = screen.getAllByText(new RegExp(`^(${technicalKinds.join("|")})$`));
  expect(shown.map((node) => node.textContent)).toEqual(technicalKinds);
  fireEvent.click(screen.getByRole("button", { name: "Hide Technical events" }));
  expect(details.getSnapshot().timeline).toHaveLength(kinds.length + 1);
  for (const kind of technicalKinds) expect(screen.queryByText(kind)).not.toBeInTheDocument();
});

test("pages technical events after filtering so bookkeeping cannot conceal messages", () => {
  const response = mockEndpointResponse();
  response.timeline = [...Array.from({ length: 250 }, (_, index) => ({
    id: `progress-${index}`, revision: 1, sourceSequence: index + 1, kind: "activity" as const,
    value: { id: `progress-${index}`, occurredAt: "2026-09-16T08:00:01.000Z",
      text: `Progress ${index}`, kind: "call" as const, eventKind: "agent_output_delivery_progressed" },
  })), ...response.timeline];
  render(<CallConsole controller={{ details: createCallDetailsStore(response) }} />);
  expect(screen.getByText("Loaded from call history")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Show Technical events" }));
  expect(screen.getAllByText(/^Progress /)).toHaveLength(100);
  fireEvent.click(screen.getByRole("button", { name: "Next conversation page" }));
  expect(screen.getAllByText(/^Progress /)).toHaveLength(100);
  fireEvent.click(screen.getByRole("button", { name: "Next conversation page" }));
  expect(screen.getByText("Loaded from call history")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Hide Technical events" }));
  expect(screen.getByText("Loaded from call history")).toBeVisible();
});
