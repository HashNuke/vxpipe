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
}: {
  scenario: CallDetailsFixtureScenario;
  theme: "dark" | "light";
}) {
  const state = useMemo(() => callDetailsFixture(scenario), [scenario]);
  return (
    <CallDetailsPage
      contextHref={(path) => adminStoryHref(path, theme)}
      state={state}
      theme={theme}
    />
  );
}
