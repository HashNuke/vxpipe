import type { CallSnapshot, VxpipeClient } from "@vxpipe/core";

export type Scenario =
  | "ready"
  | "conversation"
  | "handoff"
  | "human-handoff"
  | "phone-caller"
  | "tool-states"
  | "microphone-denied"
  | "no-alignment"
  | "ended"
  | "failed";
const initial: CallSnapshot = {
  callId: "demo-call-001",
  state: "connected",
  duration: "02:14",
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
  participants: [
    {
      id: "caller",
      name: "You",
      role: "caller",
      state: "listening",
      description: null,
      connection: { kind: "webrtc" },
      capabilities: [
        { name: "Speech to text", provider: "Deepgram", model: "flux-general-en" },
      ],
      systemPrompt: null,
      transferPolicies: [],
      tools: [],
    },
    {
      id: "assistant",
      name: "Assistant",
      role: "agent",
      state: "speaking",
      description: null,
      capabilities: [
        { name: "Language model", provider: "Google", model: "gemini-2.5-flash" },
        { name: "Text to speech", provider: "Deepgram", model: "aura-2-thalia-en" },
      ],
      systemPrompt:
        "You are the delivery concierge for Acme. Help customers check orders and reschedule deliveries. Confirm important changes before applying them.",
      transferPolicies: [
        {
          name: "Escalate to support",
          description: "Offer a human support transfer when the caller asks or a delivery change cannot be completed.",
        },
        {
          name: "Route delivery changes",
          description: "Transfer complex rescheduling requests to the delivery specialist with the current context.",
        },
      ],
      tools: [
        { name: "lookup_delivery", description: "Read the current delivery and order status." },
        { name: "update_variables", description: "Update validated call variables for this run." },
        { name: "transfer", description: "Request an allowed participant transfer." },
      ],
    },
    {
      id: "specialist",
      name: "Delivery specialist",
      role: "agent",
      state: "inactive",
      description: null,
      capabilities: [
        { name: "Language model", provider: "Google", model: "gemini-2.5-flash" },
        { name: "Text to speech", provider: "Deepgram", model: "aura-2-thalia-en" },
      ],
      systemPrompt:
        "You handle delivery rescheduling. Use the transferred context, confirm the requested window, and update the delivery only after confirmation.",
      transferPolicies: [
        {
          name: "Return to concierge",
          description: "Return unrelated questions to the delivery concierge with the current context.",
        },
      ],
      tools: [
        { name: "lookup_delivery", description: "Read the current delivery and order status." },
        { name: "reschedule_delivery", description: "Apply a confirmed delivery window." },
        { name: "transfer", description: "Request an allowed participant transfer." },
      ],
    },
    {
      id: "support",
      name: "Support teammate",
      role: "human",
      state: "inactive",
      description: null,
      capabilities: [{ name: "Voice", provider: "Browser", model: "WebRTC" }],
      systemPrompt: null,
      transferPolicies: [],
      tools: [],
    },
  ],
  messages: [
    {
      id: "m1",
      participantId: "assistant",
      time: "00:02",
      text: "Hi! I can help you arrange a delivery, check an order, or connect you with our team. What can I do for you?",
      state: "final",
      metrics: [
        {
          label: "Turn duration",
          value: 3_240,
          unit: "ms",
          source: "Turn",
          description: "Accepted input to completed response",
          scope: { kind: "participant", participantId: "assistant" },
        },
        {
          label: "TTFT",
          value: 312,
          unit: "ms",
          source: "LLM · local timing",
          description: "Model attempt dispatch to first visible text",
          scope: {
            kind: "participant-capability",
            participantId: "assistant",
            capability: "LLM",
          },
        },
        {
          label: "TPOT",
          value: 28,
          unit: "ms",
          source: "LLM · derived",
          description: "Average time per matching output token after the first",
          scope: {
            kind: "participant-capability",
            participantId: "assistant",
            capability: "LLM",
          },
        },
        {
          label: "TPS",
          value: 35.7,
          unit: "tokens/s",
          source: "LLM · derived",
          description: "Matching output tokens generated per second",
          scope: {
            kind: "participant-capability",
            participantId: "assistant",
            capability: "LLM",
          },
        },
        {
          label: "Time to first audio",
          value: 96,
          unit: "ms",
          source: "TTS · local timing",
          description: "TTS dispatch to first decoded provider audio",
          scope: {
            kind: "participant-capability",
            participantId: "assistant",
            capability: "TTS",
          },
        },
        {
          label: "RTF",
          value: 0.72,
          unit: "×",
          source: "TTS · derived",
          description: "Observed synthesis duration divided by generated audio duration",
          scope: {
            kind: "participant-capability",
            participantId: "assistant",
            capability: "TTS",
          },
        },
      ],
    },
    {
      id: "m2",
      participantId: "caller",
      time: "00:08",
      text: "I'd like to reschedule my delivery.",
      state: "final",
    },
    {
      id: "m3",
      participantId: "assistant",
      time: "00:10",
      text: "Of course. Let's find a time that works for you. Would tomorrow morning or afternoon be better?",
      state: "streaming",
      spokenRange: { start: 55, end: 63 },
      metrics: [
        {
          label: "TTFT",
          value: 284,
          unit: "ms",
          source: "LLM · local timing",
          description: "Model attempt dispatch to first visible text",
          scope: {
            kind: "participant-capability",
            participantId: "assistant",
            capability: "LLM",
          },
        },
        {
          label: "Time to first audio",
          value: 88,
          unit: "ms",
          source: "TTS · local timing",
          description: "TTS dispatch to first decoded provider audio",
          scope: {
            kind: "participant-capability",
            participantId: "assistant",
            capability: "TTS",
          },
        },
      ],
    },
  ],
  activities: [
    {
      id: "a1",
      time: "00:00",
      text: "Call connected",
      kind: "call",
    },
  ],
  toolCalls: [
    {
      id: "tool-1",
      time: "00:09",
      name: "update_variables",
      status: "completed",
    },
  ],
  events: [
    {
      id: "e1",
      protocol: "rtvi",
      type: "client-ready",
      direction: "out",
      time: "00:00.012",
      summary: "Client ready",
      details: {
        label: "rtvi-ai",
        type: "client-ready",
        data: { version: "2.1.0" },
      },
    },
    {
      id: "e2",
      protocol: "rtvi",
      type: "bot-ready",
      direction: "in",
      time: "00:00.041",
      summary: "Agent ready",
      details: {
        label: "rtvi-ai",
        type: "bot-ready",
        data: { version: "2.1.0" },
      },
    },
    {
      id: "e3",
      protocol: "rtvi",
      type: "user-transcription",
      direction: "in",
      time: "00:08.120",
      summary: "You · final transcript",
      details: {
        user_id: "caller",
        text: "I'd like to reschedule my delivery.",
        final: true,
      },
    },
    {
      id: "e4",
      protocol: "rtvi",
      type: "server-message",
      direction: "in",
      time: "00:09.420",
      summary: "Vxpipe turn progress",
      details: {
        t: "vxpipe.turn",
        v: 1,
        d: { turn_id: "turn-002", phase: "speaking" },
      },
    },
    {
      id: "e5",
      protocol: "rtvi",
      type: "bot-output",
      direction: "in",
      time: "00:10.081",
      summary: "Agent text fragment",
      details: { text: "Of course. Let's find a time that works for you." },
    },
  ],
  variables: {
    revision: 7,
    sections: {
      order: {
        revision: 1,
        value: { order_id: "ORD-1048", customer_tier: "priority" },
      },
      intake: {
        revision: 3,
        value: {
          requested_date: "2026-09-18",
          window: "afternoon",
          confirmed: false,
        },
      },
    },
  },
  metricsEnabled: true,
  metrics: [
    {
      label: "Final transcript latency",
      value: 184,
      unit: "ms",
      source: "STT · 1 turn",
      description: "Final transcript received after input audio ended",
      scope: { kind: "room-capability", capability: "STT" },
    },
    {
      label: "Median TTFT",
      value: 298,
      unit: "ms",
      source: "LLM · 2 attempts",
      description: "Median model dispatch to first visible text",
      scope: {
        kind: "participant-capability",
        participantId: "assistant",
        capability: "LLM",
      },
    },
    {
      label: "Median time to first audio",
      value: 92,
      unit: "ms",
      source: "TTS · 2 attempts",
      description: "Median TTS dispatch to first decoded provider audio",
      scope: {
        kind: "participant-capability",
        participantId: "assistant",
        capability: "TTS",
      },
    },
    {
      label: "Round-trip time",
      value: 24,
      unit: "ms",
      source: "Browser · selected ICE pair",
      description: "WebRTC connection measurement",
      scope: { kind: "participant", participantId: "caller" },
    },
    {
      label: "Input tokens",
      value: 1_842,
      unit: "tokens",
      source: "LLM provider",
      description: "Provider-reported input tokens for attributed model attempts",
      scope: {
        kind: "participant-capability",
        participantId: "assistant",
        capability: "LLM",
      },
    },
    {
      label: "Output tokens",
      value: 124,
      unit: "tokens",
      source: "LLM provider",
      description: "Provider-reported output usage, including provider token categories",
      scope: {
        kind: "participant-capability",
        participantId: "assistant",
        capability: "LLM",
      },
    },
    {
      label: "Cached tokens",
      value: 768,
      unit: "tokens",
      source: "LLM provider",
      description: "Provider-reported input tokens served from cache",
      scope: {
        kind: "participant-capability",
        participantId: "assistant",
        capability: "LLM",
      },
    },
    {
      label: "Call duration",
      value: 134,
      unit: "s",
      source: "Call lifecycle",
      description: "Elapsed time since the room opened",
      scope: { kind: "room" },
    },
  ],
};

export type ExampleScenario = "conversation" | "handoff" | "human-handoff";

function fixtureSnapshot(scenario: Scenario): CallSnapshot {
  let snapshot: CallSnapshot = structuredClone(initial);
  if (scenario === "ready")
    snapshot = {
      ...snapshot,
      state: "ready",
      duration: "00:00",
      messages: [],
      activities: [],
      toolCalls: [],
      events: [],
      participants: snapshot.participants.map((participant) => ({
        ...participant,
        state: "inactive" as const,
      })),
      variables: null,
      metrics: snapshot.metrics.map((metric) => ({ ...metric, value: null })),
    };
  if (scenario === "microphone-denied")
    snapshot = { ...snapshot, microphone: "denied" };
  if (scenario === "phone-caller")
    snapshot = {
      ...snapshot,
      participants: snapshot.participants.map((participant) =>
        participant.id === "caller"
          ? {
              ...participant,
              connection: {
                kind: "phone" as const,
                phoneNumber: "+14155550123",
              },
            }
          : participant,
      ),
    };
  if (scenario === "no-alignment")
    snapshot = {
      ...snapshot,
      alignment: "unavailable",
      devices: { ...snapshot.devices, outputSelection: false },
    };
  if (scenario === "tool-states")
    snapshot = {
      ...snapshot,
      toolCalls: [
        {
          id: "tool-1",
          time: "00:09",
          name: "lookup_delivery",
          status: "pending",
        },
        {
          id: "tool-2",
          time: "00:10",
          name: "update_variables",
          status: "completed",
          request: { requested_date: "2026-09-18" },
          response: { updated: true },
          responseStatus: 200,
        },
        {
          id: "tool-3",
          time: "00:11",
          name: "notify_customer",
          status: "failed",
          request: { channel: "sms" },
          response: { error: "Service unavailable" },
          responseStatus: 503,
        },
        {
          id: "tool-4",
          time: "00:12",
          name: "refresh_cache",
          status: "completed",
          request: null,
          response: null,
          responseStatus: 204,
        },
      ],
    };
  if (scenario === "ended" || scenario === "failed")
    snapshot = {
      ...snapshot,
      state: scenario,
      participants: snapshot.participants.map((p) => ({ ...p, state: "left" })),
      messages: snapshot.messages.map((m) => ({
        ...m,
        spokenRange: undefined,
        state: "final",
      })),
      notice:
        scenario === "failed"
          ? "The connection was lost. Your conversation is still available below."
          : "You left the call. The transcript remains available in this view.",
    };
  if (scenario === "handoff" || scenario === "human-handoff")
    snapshot = {
      ...snapshot,
      notice: undefined,
      activities: [
        ...snapshot.activities,
        {
          id: "a2",
          time: "02:13",
          text:
            scenario === "handoff"
              ? "Delivery specialist joined"
              : "Support joined",
          kind: "participant",
        },
      ],
      participants: snapshot.participants.map((participant) => {
        if (participant.id === "assistant")
          return { ...participant, state: "left" as const };
        if (scenario === "handoff" && participant.id === "specialist")
          return { ...participant, state: "speaking" as const };
        if (scenario === "human-handoff" && participant.id === "support")
          return {
            ...participant,
            state: "speaking" as const,
            connection: { kind: "webrtc" as const },
          };
        return participant;
      }),
      messages: [
        ...snapshot.messages.map((m) => ({
          ...m,
          spokenRange: undefined,
          state: "final" as const,
        })),
        {
          id: "m4",
          participantId: scenario === "handoff" ? "specialist" : "support",
          time: "02:14",
          text: "I can help with that. I have the details from your conversation, so we can pick up right here.",
          state: "streaming",
          spokenRange: { start: 0, end: 20 },
        },
      ],
    };
  return snapshot;
}

/** In-memory Storybook adapter. Never opens a socket, captures media or calls a provider. */
export function createFixtureClient(
  scenario: Scenario = "conversation",
  startScenario: ExampleScenario = "conversation",
) {
  let snapshot = fixtureSnapshot(scenario);
  const listeners = new Set<() => void>();
  const update = (changes: Partial<CallSnapshot>) => {
    snapshot = { ...snapshot, ...changes };
    listeners.forEach((listener) => listener());
  };
  const client: VxpipeClient = {
    getSnapshot: () => snapshot,
    subscribe: (listener) => {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    connect: async () => update(fixtureSnapshot(startScenario)),
    disconnect: async () =>
      update({
        state: "ended",
        microphone: "off",
        participants: snapshot.participants.map((p) => ({
          ...p,
          state: "left",
        })),
        messages: snapshot.messages.map((m) => ({
          ...m,
          spokenRange: undefined,
          state: "final",
        })),
        notice:
          "You left the call. The transcript remains available in this view.",
      }),
    sendText: async (text) => {
      if (snapshot.state !== "connected")
        throw new Error("Call is not connected");
      const id = `m${snapshot.messages.length + 1}`;
      update({
        messages: [
          ...snapshot.messages.map((m) => ({
            ...m,
            state: "final" as const,
            spokenRange: undefined,
          })),
          { id, participantId: "caller", text, time: "02:15", state: "final" },
        ],
        events: [
          ...snapshot.events,
          {
            id: `e${snapshot.events.length + 1}`,
            protocol: "rtvi",
            type: "send-text",
            direction: "out",
            time: "02:15.000",
            summary: "Typed message",
            details: { text },
          },
        ],
      });
    },
    setMicrophone: async (enabled) => {
      if (snapshot.microphone === "denied")
        throw new Error("Permission denied");
      update({ microphone: enabled ? "on" : "off" });
    },
    setSpeakerMuted: async (speakerMuted) => update({ speakerMuted }),
    selectDevice: async (kind, id) =>
      update(kind === "input" ? { inputDevice: id } : { outputDevice: id }),
  };
  return {
    ...client,
    advanceSpeech() {
      if (!snapshot.participants.some((person) => person.state === "speaking"))
        return;
      const index = snapshot.messages
        .map((message) => message.participantId !== "caller")
        .lastIndexOf(true);
      const message = snapshot.messages[index];
      if (!message || snapshot.state !== "connected") return;
      const start = message.spokenRange?.end ?? 0;
      const nextSpace = message.text.indexOf(" ", start + 1);
      const end = nextSpace === -1 ? message.text.length : nextSpace;
      const finished = start >= message.text.length;
      update({
        messages: snapshot.messages.map((m, i) =>
          i === index
            ? {
                ...m,
                spokenRange: finished ? undefined : { start, end },
                state: finished ? "final" : "streaming",
              }
            : m,
        ),
        participants: snapshot.participants.map((p) =>
          p.role === "agent" && p.state !== "left"
            ? { ...p, state: finished ? "listening" : "speaking" }
            : p,
        ),
      });
    },
  };
}
