import type { CatalogCapability } from "../modelCatalog";

export type JsonValue = null | boolean | number | string | JsonValue[] | { [key: string]: JsonValue };
export type JsonObject = { [key: string]: JsonValue };
export type CapabilitySelection = {
  provider: string;
  model: string;
  credential_name?: string;
  options?: JsonObject;
  provider_options?: JsonObject;
};
export type Capabilities = Partial<Record<CatalogCapability, CapabilitySelection>>;
export type Connection = {
  service: string;
  mode: "receive" | "dial";
  admission?: "start_call" | "transfer";
  number?: string;
  number_from_variable?: { section: string; variable: string };
};
export type FirstMessage = { mode: "wait_for_input" | "generated" } | { mode: "fixed"; text: string };
export type TransferHistory =
  | { mode: "fresh" | "all_spoken" | "selected" }
  | { mode: "last_n_spoken"; turns: number };
export type ToolSelection = {
  type: "host" | "mcp" | "platform";
  tool: string;
  integration?: string;
  conversation_mode?: "blocking" | "non_blocking";
};
export type MediaPolicy = {
  audio_routes?: Record<string, string[]>;
  transcript_routes?: Record<string, string[]>;
  record_audio?: boolean;
  save_transcripts?: boolean;
};
export type VariablePermission = ["read"] | ["read", "write"] | ["write", "read"];
export type ParticipantBase = {
  description?: string | null;
  capabilities?: Capabilities;
  while_present?: MediaPolicy;
};
export type HumanParticipant = ParticipantBase & {
  type: "human";
  connection: Connection;
  transfer_notice?: string | null;
};
export type AgentParticipant = ParticipantBase & {
  type: "agent";
  prompt: string;
  first_message?: FirstMessage;
  tools?: Record<string, ToolSelection>;
  transfers?: string[];
  transfer_history?: TransferHistory | null;
  variable_permissions?: Record<string, VariablePermission>;
};
export type Participant = HumanParticipant | AgentParticipant;
export type VariableType = "array" | "boolean" | "integer" | "null" | "number" | "object" | "string";
export type VariableSchema = {
  type?: VariableType | VariableType[];
  properties?: Record<string, VariableSchema>;
  required?: string[];
  additionalProperties?: boolean;
  enum?: JsonValue[];
  items?: VariableSchema;
  minimum?: number;
  maximum?: number;
  exclusiveMinimum?: number;
  exclusiveMaximum?: number;
  minItems?: number;
  maxItems?: number;
  minLength?: number;
  maxLength?: number;
};
export type VariableSection = { schema: VariableSchema };
export type WaitSoundSlot = "call_setup" | "transfer_to_agent" | "transfer_to_human" | "transfer_joining";
export type WaitSounds = Partial<Record<WaitSoundSlot, string | null>> | null;
export type OpeningAudio =
  | { type: "text"; text: string; text_to_speech: CapabilitySelection }
  | { type: "file_url"; url: string };
export type Visibility = "hidden" | "metadata" | "full";

// Optional fields stay omitted until explicitly edited. Parsing never inserts defaults.
export type CallSpecSource = {
  schema_version: "20261004.01" | "20260915.01";
  name?: string | null;
  incoming_call?: { caller: string; handled_by: string };
  outgoing_call?: { callee: string; handled_by: string; ring_timeout_ms?: number };
  entry_caller?: string;
  entry_receiver?: string;
  participants: Record<string, Participant>;
  defaults?: { capabilities?: Capabilities };
  opening_audio?: OpeningAudio | null;
  wait_sounds?: WaitSounds;
  media_policy?: MediaPolicy;
  call_variables?: { sections?: Record<string, VariableSection> };
  transfer_policy?: { attempt_timeout_ms?: number } | null;
  tool_visibility?: Visibility;
  tool_visibility_overrides?: Record<string, Record<string, Visibility>>;
  limits?: { max_duration_ms?: number };
};
export type SourceDocument = { source: CallSpecSource; readOnly: boolean; notice?: string };
export type SourceIssue = { code: string; path: string[]; reason: string };
