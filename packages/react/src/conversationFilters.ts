export type ConversationFilter = "messages" | "logs" | "events" | "tools" | "technical";
export type ConversationFilters = Record<ConversationFilter, boolean>;

export const defaultConversationFilters: ConversationFilters = {
  messages: true,
  logs: false,
  events: true,
  technical: false,
  tools: true,
};

export const conversationFilterLabels: Record<ConversationFilter, string> = {
  messages: "Messages",
  logs: "Logs",
  events: "Events",
  technical: "Technical events",
  tools: "Tool calls",
};

export const conversationFilterOrder = Object.keys(
  defaultConversationFilters,
) as ConversationFilter[];

const technicalEventKinds = new Set([
  "usage_observed",
  "agent_output_delivery_progressed",
  "agent_output_delivered",
  "agent_output_delivery_started",
  "participant_transcription_final",
  "participant_turn_started",
  "agent_turn_completed",
]);

/** Legacy and unknown kinds stay visible, including all failure/lifecycle evidence. */
export function isTechnicalEvent(eventKind: string | undefined): boolean {
  return eventKind !== undefined && technicalEventKinds.has(eventKind);
}
