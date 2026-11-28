import { useMemo } from "react";
import type { HistoryFilters } from "@vxpipe/react";
import { CallDetailsPage } from "../CallDetailsPage";
import { StoryCallBreadcrumbs } from "./StoryCallBreadcrumbs";
import { inspectionFixture, type GuardrailScenario } from "./guardrailInspectionFixtures";

const allHistory: HistoryFilters = {
  messages: "Show", logs: "Show", events: "Call + technical events", tools: "With details", guardrails: "All",
};
const failureHistory: HistoryFilters = {...allHistory, logs: "Hide", events: "Call events", guardrails: "Only failures"};

export function GuardrailCallDetails({scenario, theme, initialTab = "Conversation"}: {
  scenario: GuardrailScenario; theme: "light" | "dark"; initialTab?: "Conversation" | "Metrics";
}) {
  const state = useMemo(() => inspectionFixture(scenario), [scenario]);
  const defaults = ["pass", "partial-answer", "multiple-agents"].includes(scenario) ? allHistory : failureHistory;
  return <div style={{height: "100dvh"}}>
    <CallDetailsPage key={scenario} state={state} theme={theme} initialHistoryFilters={defaults}
      initialTab={initialTab === "Metrics" ? "metrics" : "chat"}
      renderNavigationHeader={state => <StoryCallBreadcrumbs state={state} theme={theme} />} />
  </div>;
}
