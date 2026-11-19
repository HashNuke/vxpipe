import { createLatencyFixture } from "../../../../../packages/react/stories/latencyFixtures";
import { StoryCallBreadcrumbs } from "./stories/StoryCallBreadcrumbs";
import { AdminJourneyStory } from "./AdminJourneyStory";
import { adminStoryRoute } from "./adminStoryRoute";
import { useMemo } from "react";

import { CallDetailsPage } from "./CallDetailsPage";
import { adminStoryHref } from "./adminStoryHref";
import {
  callDetailsFixture,
  type CallDetailsFixtureScenario,
} from "./callDetailsFixtures";

export function CallDetailsStory({
  scenario,
  theme,
  initialTab = "chat",
  latency = false,
}: {
  scenario: CallDetailsFixtureScenario;
  latency?: boolean;
  theme: "dark" | "light";
  initialTab?: "chat" | "variables" | "metrics" | "participants";
}) {
  const state = useMemo(() => {
    const value = callDetailsFixture(scenario);
    return latency && value.status === "ready"
      ? { ...value, controller: { ...value.controller, latency: createLatencyFixture() } }
      : value;
  }, [scenario, latency]);
  if (adminStoryRoute(window.location.hash).page === "call-details") return <AdminJourneyStory theme={theme} />;
  return (
    <CallDetailsPage
      renderNavigationHeader={state => <StoryCallBreadcrumbs state={state} theme={theme} />}
      contextHref={(path) => adminStoryHref(path, theme)}
      state={state}
      initialTab={initialTab}
      theme={theme}
    />
  );
}
