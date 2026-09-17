export type ConversationFilter = "messages" | "logs" | "events" | "tools";
export type ConversationFilters = Record<ConversationFilter, boolean>;

export const defaultConversationFilters: ConversationFilters = {
  messages: true,
  logs: false,
  events: true,
  tools: true,
};

export const conversationFilterLabels: Record<ConversationFilter, string> = {
  messages: "Messages",
  logs: "Logs",
  events: "Events",
  tools: "Tool calls",
};

export const conversationFilterOrder = Object.keys(
  defaultConversationFilters,
) as ConversationFilter[];
