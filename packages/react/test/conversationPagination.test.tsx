import { act, fireEvent, render, screen } from "@testing-library/react";
import { expect, test } from "vitest";
import { createCallDetailsStore, type CallDetailsTimelineEntity } from "@vxpipe/core";
import { CallConsole } from "../src/index.js";
import { createFixtureController } from "../stories/fixtureClient.js";

function message(index: number): CallDetailsTimelineEntity {
  return {
    id: `live-${index}`, revision: 1, sourceSequence: index, kind: "message",
    value: { id: `live-${index}`, occurredAt: new Date(Date.UTC(2026, 8, 16, 22, 30, index)).toISOString(),
      participantId: "support", text: `Live message ${index}`, state: "final" },
  };
}

test("a watcher on the latest live page continues seeing new speech across a page boundary", () => {
  const fixture = createFixtureController("conversation");
  const initial = fixture.details.getSnapshot();
  const details = createCallDetailsStore({ ...initial, timeline: Array.from({ length: 100 }, (_, index) => message(index + 1)) });
  render(<CallConsole controller={{ details, live: fixture.live }} />);
  expect(screen.getByText("Live message 100")).toBeVisible();
  act(() => { details.apply({ type: "timeline-upsert", callId: initial.call.id, entity: message(101) }); });
  expect(details.getSnapshot().timeline).toHaveLength(101);
  expect(screen.getByText("Live message 101")).toBeVisible();
});

test("starting from ready also follows speech across the first page boundary", async () => {
  const fixture = createFixtureController("ready");
  const details = createCallDetailsStore(fixture.details.getSnapshot());
  render(<CallConsole controller={{ details, live: fixture.live }} />);
  await act(async () => {
    await fixture.live!.connect();
    details.replaceBaseline({ ...fixture.details.getSnapshot(), timeline: Array.from({ length: 100 }, (_, index) => message(index + 1)) });
  });
  expect(screen.getByText("Live message 100")).toBeVisible();
  act(() => { details.apply({ type: "timeline-upsert", callId: details.getSnapshot().call.id, entity: message(101) }); });
  expect(details.getSnapshot().timeline).toHaveLength(101);
  expect(screen.getByText("Live message 101")).toBeVisible();
});

test("live updates preserve explicit browsing of an earlier page", () => {
  const fixture = createFixtureController("conversation");
  const initial = fixture.details.getSnapshot();
  const details = createCallDetailsStore({ ...initial, timeline: Array.from({ length: 101 }, (_, index) => message(index + 1)) });
  render(<CallConsole controller={{ details, live: fixture.live }} />);
  fireEvent.click(screen.getByRole("button", { name: "Previous conversation page" }));
  expect(screen.getByText("Live message 1")).toBeVisible();
  act(() => { details.apply({ type: "timeline-upsert", callId: initial.call.id, entity: message(102) }); });
  expect(screen.getByText("Live message 1")).toBeVisible();
  expect(screen.queryByText("Live message 102")).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole("button", { name: "Next conversation page" }));
  expect(screen.getByText("Live message 102")).toBeVisible();
});

test("diagnostic transcript links open the matching participant turn on its bounded page", async () => {
  const { createLatencyFixture } = await import("../stories/latencyFixtures.js");
  const fixture = createFixtureController("conversation");
  const timeline = Array.from({ length: 205 }, (_, index) => message(index + 1));
  const target = timeline[150]!;
  if (target.kind !== "message") throw new Error("Expected message");
  target.value = { ...target.value, participantId: "caller", turnId: "turn-one" };
  const wrong = timeline[0]!;
  if (wrong.kind !== "message") throw new Error("Expected message");
  wrong.value = { ...wrong.value, turnId: "turn-one" };
  const details = createCallDetailsStore({ ...fixture.details.getSnapshot(), timeline });
  render(<CallConsole controller={{ details, latency: createLatencyFixture() }} />);
  fireEvent.click(screen.getByRole("button", { name: "Hide Messages" }));
  fireEvent.click(screen.getByRole("button", { name: "Metrics" }));
  fireEvent.click(screen.getByRole("button", { name: "Latency diagnostics" }));
  fireEvent.click(await screen.findByRole("button", { name: "View transcript for turn 1" }));
  expect(screen.getByText("Live message 151")).toBeVisible();
  expect(screen.getByText("Page 2 of 3")).toBeVisible();
  expect(screen.getAllByRole("article")).toHaveLength(100);
  expect(document.activeElement).toHaveTextContent("Live message 151");
  fireEvent.click(screen.getByRole("button", { name: "Next conversation page" }));
  expect(screen.getByText("Live message 205")).toBeVisible();
});
