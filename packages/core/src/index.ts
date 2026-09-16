/** Public prototype contract. Real RTVI/WebRTC adapters are a later milestone. */
export interface Participant {
  id: string;
  name: string;
  role: "caller" | "agent" | "human";
  state: "inactive" | "listening" | "speaking" | "left";
  description: string;
  /** Present for callers when the admission method is safe to display. */
  connection?: ParticipantConnection;
  capabilities: readonly ParticipantCapability[];
  /** Included only by an authorized configuration projection. */
  systemPrompt: string | null;
  transferPolicies: readonly ParticipantTransferPolicy[];
  tools: readonly ParticipantTool[];
}

export type ParticipantConnection =
  | { kind: "webrtc" }
  | {
      kind: "phone";
      /** Normalized E.164 number. */
      phoneNumber: string;
    };

export interface ParticipantCapability {
  name: string;
  provider: string;
  model?: string;
}

export interface ParticipantTransferPolicy {
  name: string;
  description: string;
}

export interface ParticipantTool {
  name: string;
  description: string;
}

export interface Message {
  id: string;
  participantId: string;
  text: string;
  time: string;
  state: "final" | "streaming" | "interrupted";
  /** Character range supplied by the client, never estimated by the React view. */
  spokenRange?: { start: number; end: number };
  /** Measurements correlated to this exact turn by the adapter. */
  metrics?: readonly Metric[];
}

export interface ProtocolEvent {
  id: string;
  protocol: string;
  type: string;
  direction: "in" | "out";
  time: string;
  summary: string;
  /** Safe display data supplied by the adapter, excluding admission/auth secrets. */
  details: Readonly<Record<string, unknown>>;
}

export interface ActivityEvent {
  id: string;
  time: string;
  text: string;
  kind: "call" | "participant" | "transfer";
}

export interface ToolCall {
  id: string;
  time: string;
  name: string;
  status: "pending" | "completed" | "failed";
  /** Display-safe payloads supplied only when capture is enabled; null means empty. */
  request?: JsonValue;
  response?: JsonValue;
  /** HTTP status captured by an HTTP-backed tool adapter, when applicable. */
  responseStatus?: number;
}

export interface Metric {
  label: string;
  value: number | null;
  unit: string;
  source: string;
  description: string;
  scope: MetricScope;
}

export type MetricScope =
  | { kind: "room" }
  | { kind: "room-capability"; capability: string }
  | { kind: "participant"; participantId: string }
  | {
      kind: "participant-capability";
      participantId: string;
      capability: string;
    };

export type JsonValue =
  | string
  | number
  | boolean
  | null
  | readonly JsonValue[]
  | { readonly [key: string]: JsonValue };

export interface VariableSection {
  revision: number;
  value: JsonValue;
}

export interface VariableSnapshot {
  revision: number;
  sections: Readonly<Record<string, VariableSection>>;
}

export interface CallSnapshot {
  callId: string;
  state: "ready" | "connected" | "ended" | "failed";
  duration: string;
  participants: readonly Participant[];
  messages: readonly Message[];
  activities: readonly ActivityEvent[];
  toolCalls: readonly ToolCall[];
  events: readonly ProtocolEvent[];
  metrics: readonly Metric[];
  metricsEnabled: boolean;
  /** Latest full projection authorized for this client; null when unavailable. */
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

/** Each snapshot keeps its identity until an update; subscriptions return cleanup. */
export interface VxpipeClient {
  getSnapshot(): CallSnapshot;
  subscribe(listener: () => void): () => void;
  connect(): Promise<void>;
  disconnect(): Promise<void>;
  sendText(text: string): Promise<void>;
  setMicrophone(enabled: boolean): Promise<void>;
  setSpeakerMuted(muted: boolean): Promise<void>;
  selectDevice(kind: "input" | "output", id: string): Promise<void>;
}
