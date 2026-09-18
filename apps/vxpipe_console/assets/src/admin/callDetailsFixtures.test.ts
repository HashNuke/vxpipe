import { expect, test } from "vitest";

import { calls, demoCallSpec } from "./callFixtures";
import {
  callDetailsFixture,
  callDetailsFixtureForCall,
} from "./callDetailsFixtures";
import { demoTenant } from "./callSpecFixtures";

test("the ongoing fixture publishes submitted composer text", async () => {
  const state = callDetailsFixture("ongoing");
  expect(state.status).toBe("ready");
  if (state.status !== "ready") return;

  await state.controller.live?.sendText("Please confirm tomorrow morning.");

  expect(state.controller.details.getSnapshot().timeline).toEqual(
    expect.arrayContaining([
      expect.objectContaining({
        kind: "message",
        value: expect.objectContaining({
          participantId: "caller",
          text: "Please confirm tomorrow morning.",
        }),
      }),
    ]),
  );
});

test("fixture events stay within calls that actually started", () => {
  for (const call of calls) {
    const state = callDetailsFixtureForCall(call, demoCallSpec, demoTenant);
    expect(state.status).toBe("ready");
    if (state.status !== "ready") continue;

    const snapshot = state.controller.details.getSnapshot();
    const occurrences = snapshot.timeline.map((entity) =>
      Date.parse(entity.value.occurredAt),
    );

    if (call.startedAt === null) {
      expect(snapshot.timeline).toHaveLength(0);
      expect(snapshot.participants.every(({ value }) => value.state === "inactive")).toBe(
        true,
      );
      expect(snapshot.metrics.some(({ value }) => value.label === "TTFT")).toBe(false);
      if (call.state === "prepared") expect(snapshot.incarnation).toBeNull();
    } else {
      expect(occurrences.every((instant) => instant >= Date.parse(call.startedAt!))).toBe(
        true,
      );
      if (call.endedAt) {
        expect(occurrences.every((instant) => instant <= Date.parse(call.endedAt!))).toBe(
          true,
        );
      }
    }
  }
});

test("the long-content fixture provides long call context and console content", () => {
  const state = callDetailsFixture("long-content");
  expect(state.status).toBe("ready");
  if (state.status !== "ready") return;

  expect(state.tenant.name.length).toBeGreaterThan(50);
  expect((state.callSpec?.name ?? "").length).toBeGreaterThan(50);

  const snapshot = state.controller.details.getSnapshot();
  const assistant = snapshot.participants.find(({ id }) => id === "assistant");
  const message = snapshot.timeline.find(({ id }) => id === "message-2");
  expect(assistant?.value.systemPrompt?.length).toBeGreaterThan(150);
  expect(message?.kind).toBe("message");
  if (!message || message.kind !== "message") return;
  expect(message.value.text.length).toBeGreaterThan(150);
});
