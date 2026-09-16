import type {
  ActivityEvent,
  Message,
  Metric,
  Participant,
  ProtocolEvent,
  ToolCall,
  VariableSnapshot,
} from "@vxpipe/core";

/** Derived React view model; durable and browser-local state remain separate in Core. */
export interface ConsoleSnapshot {
  callId: string;
  state: "ready" | "connected" | "ended" | "failed";
  duration: string | null;
  participants: readonly Participant[];
  messages: readonly Message[];
  activities: readonly ActivityEvent[];
  toolCalls: readonly ToolCall[];
  events: readonly ProtocolEvent[];
  metrics: readonly Metric[];
  metricsEnabled: boolean;
  metricsAvailability: "available" | "unavailable";
  variables: VariableSnapshot | null;
  alignment: "word" | "segment" | "unavailable";
  microphone: "off" | "on" | "denied";
  speakerMuted: boolean;
  inputDevice: string;
  outputDevice: string;
  devices: {
    inputs: readonly string[];
    outputs: readonly string[];
    outputSelection: boolean;
  };
  notice?: string;
}
