import type { ConversationFilters } from "./conversationFilters.js";

export const historyOptions = {
  messages: ["Hide", "Show"],
  logs: ["Hide", "Show"],
  events: ["Hide", "Call events", "Call + technical events"],
  tools: ["Hide", "Only calls", "With details"],
  guardrails: ["Hide", "Only failures", "All"],
} as const;

export type HistoryFilters = {
  [K in keyof typeof historyOptions]: (typeof historyOptions)[K][number];
};

/** Call Details opens on public turns, executed calls and failed checks. */
export const defaultHistoryFilters: HistoryFilters = {
  messages: "Show", logs: "Hide", events: "Hide", tools: "Only calls", guardrails: "Only failures",
};

export const allHistoryFilters: HistoryFilters = {
  messages: "Show", logs: "Show", events: "Call + technical events", tools: "With details", guardrails: "All",
};

export function conversationVisibility(filters: HistoryFilters): ConversationFilters {
  return {
    messages: filters.messages === "Show", logs: filters.logs === "Show",
    events: filters.events !== "Hide", technical: filters.events === "Call + technical events",
    tools: filters.tools !== "Hide",
  };
}
