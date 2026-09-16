/** Public presentation types shared by Core adapters and React components. */
export interface Participant {
  id: string;
  name: string;
  role: "caller" | "agent" | "human";
  state: "inactive" | "listening" | "speaking" | "left";
  description: string | null;
  connection?: ParticipantConnection;
  capabilities: readonly ParticipantCapability[];
  systemPrompt: string | null;
  transferPolicies: readonly ParticipantTransferPolicy[];
  tools: readonly ParticipantTool[];
}

export type ParticipantConnection =
  | { kind: "webrtc" }
  | { kind: "phone"; phoneNumber: string };

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
  /** UTC RFC 3339 instant when this item occurred. */
  occurredAt: string;
  state: "final" | "streaming" | "interrupted";
  spokenRange?: { start: number; end: number };
  metrics?: readonly Metric[];
}

export interface ProtocolEvent {
  id: string;
  protocol: string;
  type: string;
  direction: "in" | "out";
  /** UTC RFC 3339 instant when this item occurred. */
  occurredAt: string;
  summary: string;
  details: Readonly<Record<string, unknown>>;
}

export interface ActivityEvent {
  id: string;
  /** UTC RFC 3339 instant when this item occurred. */
  occurredAt: string;
  text: string;
  kind: "call" | "participant" | "transfer";
}

export interface ToolCall {
  id: string;
  /** UTC RFC 3339 instant when this item occurred. */
  occurredAt: string;
  name: string;
  status: "pending" | "completed" | "failed";
  request?: JsonValue;
  response?: JsonValue;
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
