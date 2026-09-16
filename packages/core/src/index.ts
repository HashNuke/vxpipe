/** Public prototype contract. Real RTVI/WebRTC adapters are a later milestone. */
export interface Participant {
  id: string;
  name: string;
  role: "caller" | "agent" | "human";
  state: "listening" | "speaking" | "waiting" | "left";
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

export interface Metric {
  label: string;
  value: number | null;
  unit: string;
  source: string;
  description: string;
}

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
  events: readonly ProtocolEvent[];
  metrics: readonly Metric[];
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
