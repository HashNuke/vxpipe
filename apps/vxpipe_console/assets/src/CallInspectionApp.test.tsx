import { latencyResponseFixture } from "./test/latencyResponseFixture";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
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
        {controller.latency && <button onClick={() => void controller.latency!.report(null, new AbortController().signal).catch(() => {})}>Load latency report</button>}
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


test("remote inspection provides diagnostics lazily and independently from its history loader", async () => {
  const fetchImpl = vi.fn().mockResolvedValue(new Response(JSON.stringify(latencyResponseFixture())));
  vi.stubGlobal("fetch", fetchImpl);
  try {
    const loader = { refresh: vi.fn(async () => snapshot("ended")) };
    render(<CallInspectionApp tenantKey="tenant-key" callId="call-public-id" loader={loader} />);
    expect(await screen.findByText("Loaded from call history")).toBeVisible();
    expect(fetchImpl).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Load latency report" }));
    await waitFor(() => expect(fetchImpl).toHaveBeenCalledWith(
      "/api/tenants/tenant-key/calls/call-public-id/latency", expect.objectContaining({ cache: "no-store" }),
    ));
    expect(loader.refresh).toHaveBeenCalledTimes(1);
  } finally { vi.unstubAllGlobals(); }
});

test("revalidates inspection on reconnect and hides a previously readable call after a rejection", async () => {
  const loader = {refresh: vi.fn()
    .mockResolvedValueOnce(snapshot("running"))
    .mockRejectedValueOnce(new Error("access expired"))
    .mockResolvedValueOnce(snapshot("ended"))};
  const {unmount} = render(<CallInspectionApp tenantKey="tenant-1" callId="call-1" loader={loader} />);
  expect(await screen.findByText("In progress")).toBeVisible();
  fireEvent(window, new Event("online"));
  expect(await screen.findByRole("alert")).toHaveTextContent("Call inspection is unavailable");
  expect(screen.queryByText("Loaded from call history")).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", {name:"Retry"}));
  expect(await screen.findByText("Call ended")).toBeVisible();
  unmount();
  fireEvent(window, new Event("online"));
  expect(loader.refresh).toHaveBeenCalledTimes(3);
});

test("refreshes a visible running call and stops polling once the stored call ends", async () => {
  vi.useFakeTimers({shouldAdvanceTime: true});
  try {
    const loader = { refresh: vi.fn().mockResolvedValueOnce(snapshot("running")).mockResolvedValue(snapshot("ended")) };
    render(<CallInspectionApp tenantKey="tenant-1" callId="call-1" loader={loader} />);
    expect(await screen.findByText("In progress")).toBeVisible();
    await vi.advanceTimersByTimeAsync(10000);
    expect(loader.refresh).toHaveBeenCalledTimes(2);
    await vi.advanceTimersByTimeAsync(30000);
    expect(loader.refresh).toHaveBeenCalledTimes(2);
  } finally {
    vi.useRealTimers();
  }
});
