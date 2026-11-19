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
}: {
  scenario: CallDetailsFixtureScenario;
  theme: "dark" | "light";
  initialTab?: "chat" | "variables" | "metrics" | "participants";
}) {
  const state = useMemo(() => callDetailsFixture(scenario), [scenario]);
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
