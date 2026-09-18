import {
  createCallDetailsStore,
  type CallConsoleController,
  type CallDetailsSnapshot,
  type LocalSessionSnapshot,
} from "@vxpipe/core";

import { calls, demoCallSpec } from "./callFixtures";
import type { CallSummary, CallSpecContext } from "./callTypes";
import type { CallDetailsPageState } from "./callDetailsTypes";
import { demoTenant } from "./callSpecFixtures";
import type { TenantContext } from "./callSpecTypes";

export type CallDetailsFixtureScenario =
  | "ongoing"
  | "ended"
  | "partial-archive"
  | "long-content"
  | "loading"
  | "unavailable"
  | "malformed-response";

const longTenant: TenantContext = {
  key: "tn_regional_delivery_customer_experience_operations_southeast_asia",
  name: "Regional delivery and customer experience operations — Southeast Asia",
};

const longCallSpec: CallSpecContext = {
  ...demoCallSpec,
  id: "international-delivery-rescheduling-and-customer-resolution",
  name: "International delivery rescheduling and customer resolution",
};

function snapshot(
  selectedCall: CallSummary,
  completeness: "complete" | "incomplete" | "unconfirmed",
  content: "default" | "long" = "default",
): CallDetailsSnapshot {
  const ended = selectedCall.state === "ended" || selectedCall.state === "failed";
  const durationMs =
    selectedCall.startedAt && selectedCall.endedAt
      ? Date.parse(selectedCall.endedAt) - Date.parse(selectedCall.startedAt)
      : selectedCall.state === "running"
        ? 134_000
        : null;
  const occurredAt = (seconds: number) =>
    new Date(
      Date.parse(selectedCall.startedAt ?? selectedCall.createdAt) + seconds * 1_000,
    ).toISOString();
  return {
    schemaVersion: 1,
    call: {
      id: selectedCall.id,
      revision: 4,
      state: selectedCall.state,
      createdAt: selectedCall.createdAt,
      startedAt: selectedCall.startedAt,
      endedAt: selectedCall.endedAt,
      terminalReason: selectedCall.terminalReason,
      durationMs,
    },
    incarnation:
      selectedCall.state === "prepared"
        ? null
        : { roomId: "room-demo-01", incarnationId: "run-demo-01" },
    participants: [
      {
        id: "caller",
        revision: 1,
        value: {
          id: "caller",
          name: "Caller",
          role: "caller",
          state: selectedCall.startedAt === null ? "inactive" : ended ? "left" : "listening",
          description: null,
          connection: { kind: "webrtc" },
          capabilities: [
            { name: "Audio input", provider: "Browser" },
            { name: "Speech to text", provider: "Deepgram", model: "flux-general-en" },
          ],
          systemPrompt: null,
          transferPolicies: [],
          tools: [],
        },
      },
      {
        id: "assistant",
        revision: 2,
        value: {
          id: "assistant",
          name: "Assistant",
          role: "agent",
          state: selectedCall.startedAt === null ? "inactive" : ended ? "left" : "speaking",
          description: null,
          capabilities: [
            { name: "Language model", provider: "Google", model: "gemini-2.5-flash" },
            { name: "Text to speech", provider: "Deepgram", model: "aura-2-thalia-en" },
          ],
          systemPrompt:
            content === "long"
              ? "Help callers coordinate international delivery changes across multiple time zones, confirm every address and scheduling constraint, explain the available alternatives clearly, and obtain explicit confirmation before applying any change to the shipment."
              : "Help callers reschedule deliveries and confirm changes before applying them.",
          transferPolicies: [
            { name: "Support", description: "Transfer when a delivery change needs a teammate." },
          ],
          tools: [
            { name: "update_variables", description: "Update validated call variables." },
          ],
        },
      },
    ],
    timeline: selectedCall.startedAt ? [
      {
        id: "activity-1",
        revision: 1,
        sourceSequence: 1,
        kind: "activity",
        value: {
          id: "activity-1",
          occurredAt: occurredAt(1),
          text: "Call connected",
          kind: "call",
        },
      },
      {
        id: "message-1",
        revision: 1,
        sourceSequence: 2,
        kind: "message",
        value: {
          id: "message-1",
          participantId: "caller",
          text: "I'd like to reschedule my delivery.",
          occurredAt: occurredAt(8),
          state: "final",
        },
      },
      {
        id: "tool-1",
        revision: 1,
        sourceSequence: 3,
        kind: "tool-call",
        value: {
          id: "tool-1",
          occurredAt: occurredAt(9),
          name: "update_variables",
          status: "completed",
          request: { delivery_date: "2026-09-18" },
          response: { updated: true },
          responseStatus: 200,
        },
      },
      {
        id: "message-2",
        revision: 1,
        sourceSequence: 4,
        kind: "message",
        value: {
          id: "message-2",
          participantId: "assistant",
          text:
            content === "long"
              ? "Tomorrow morning is available between 8:00 AM and 11:30 AM in the destination time zone. Before I confirm it, please verify that the receiving address, building access instructions, and contact telephone number are still correct for the courier."
              : "Tomorrow morning is available. Would you like me to confirm it?",
          occurredAt: occurredAt(10),
          state: selectedCall.state === "running" ? "streaming" : "final",
          ...(selectedCall.state === "running"
            ? { spokenRange: { start: 0, end: 34 } }
            : {}),
        },
      },
      {
        id: "event-1",
        revision: 1,
        sourceSequence: 5,
        kind: "protocol-event",
        value: {
          id: "event-1",
          protocol: "rtvi",
          type: "bot-ready",
          direction: "in",
          occurredAt: occurredAt(2),
          summary: "Agent ready",
          details: { version: "2.1.0" },
        },
      },
    ] : [],
    variables: {
      state: "available",
      value: {
        revision: 2,
        sections: {
          delivery: { revision: 2, value: { requested_date: "2026-09-18" } },
        },
      },
    },
    metrics: selectedCall.startedAt ? [
      {
        id: "metric-1",
        revision: 1,
        value: {
          label: "Call duration",
          value: durationMs,
          unit: "ms",
          source: "Call lifecycle",
          description: "Elapsed call duration",
          scope: { kind: "room" },
        },
      },
      {
        id: "metric-2",
        revision: 1,
        value: {
          label: "TTFT",
          value: 284,
          unit: "ms",
          source: "LLM · local timing",
          description: "Model dispatch to first visible text",
          scope: {
            kind: "participant-capability",
            participantId: "assistant",
            capability: "LLM",
          },
        },
      },
    ] : [],
    metricsAvailability: { state: "available" },
    completeness: {
      state: completeness,
      missingSequenceCount: completeness === "incomplete" ? 2 : 0,
      droppedLiveRecords: 0,
    },
  };
}

function liveController(
  details: ReturnType<typeof createCallDetailsStore>,
  call: CallSummary,
): CallConsoleController["live"] {
  let local: LocalSessionSnapshot = {
    connectionState: "connected",
    alignment: "word",
    microphone: "off",
    speakerMuted: false,
    inputDevice: "Built-in microphone",
    outputDevice: "System output",
    devices: {
      inputs: ["Built-in microphone", "USB headset"],
      outputs: ["System output", "USB headset"],
      outputSelection: true,
    },
  };
  const listeners = new Set<() => void>();
  let messageSequence = 0;
  const publish = (next: LocalSessionSnapshot) => {
    local = next;
    listeners.forEach((listener) => listener());
  };
  return {
    getSnapshot: () => local,
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    connect: async () => publish({ ...local, connectionState: "connected" }),
    disconnect: async () => publish({ ...local, connectionState: "ready" }),
    sendText: async (text) => {
      messageSequence += 1;
      details.apply({
        type: "timeline-upsert",
        callId: call.id,
        ...(details.getSnapshot().incarnation
          ? { incarnationId: details.getSnapshot().incarnation!.incarnationId }
          : {}),
        entity: {
          id: `composer-${messageSequence}`,
          revision: 1,
          sourceSequence: details.getSnapshot().timeline.length + messageSequence,
          kind: "message",
          value: {
            id: `composer-${messageSequence}`,
            participantId: "caller",
            text,
            occurredAt: new Date(
              Date.parse(call.startedAt ?? call.createdAt) + (12 + messageSequence) * 1_000,
            ).toISOString(),
            state: "final",
          },
        },
      });
    },
    setMicrophone: async (enabled) =>
      publish({ ...local, microphone: enabled ? "on" : "off" }),
    setSpeakerMuted: async (muted) =>
      publish({ ...local, speakerMuted: muted }),
    selectDevice: async (kind, id) =>
      publish({
        ...local,
        ...(kind === "input" ? { inputDevice: id } : { outputDevice: id }),
      }),
  };
}

function readyState(
  selectedCall: CallSummary,
  completeness: "complete" | "incomplete" | "unconfirmed",
  callSpec: CallSpecContext = demoCallSpec,
  tenant: TenantContext = demoTenant,
  content: "default" | "long" = "default",
): CallDetailsPageState {
  const details = snapshot(selectedCall, completeness, content);
  const store = createCallDetailsStore(details);
  const controller: CallConsoleController = {
    details: store,
    ...(selectedCall.state === "running"
      ? { live: liveController(store, selectedCall) }
      : {}),
  };
  return {
    status: "ready",
    tenant,
    callSpec,
    callId: details.call.id,
    callSpecRevision: selectedCall.callSpecRevision,
    controller,
    completeness,
  };
}

export function callDetailsFixture(
  scenario: CallDetailsFixtureScenario,
): CallDetailsPageState {
  if (scenario === "ongoing") return readyState(calls[0], "unconfirmed");
  if (scenario === "ended") return readyState(calls[1], "complete");
  if (scenario === "partial-archive") return readyState(calls[1], "incomplete");
  if (scenario === "long-content") {
    return readyState(calls[0], "unconfirmed", longCallSpec, longTenant, "long");
  }

  const call = calls[0];
  const context = {
    tenant: demoTenant,
    callSpec: demoCallSpec,
    callId: call.id,
    callSpecRevision: call.callSpecRevision,
  };
  if (scenario === "loading") return { status: "loading", ...context };
  if (scenario === "unavailable") {
    return {
      status: "unavailable",
      ...context,
      message: "Call inspection is unavailable. Try again after storage is available.",
    };
  }
  return {
    status: "malformed",
    ...context,
    message: "The inspection response did not match the supported call-details schema.",
  };
}

export function callDetailsFixtureForCall(
  call: CallSummary,
  callSpec: CallSpecContext,
  tenant: TenantContext,
): CallDetailsPageState {
  return readyState(call, call.archiveState, callSpec, tenant);
}
