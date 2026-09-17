import { useMemo } from "react";

import { CallDetailsPage } from "./CallDetailsPage";
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
  const tenantPath = `/admin/tenants/${encodeURIComponent(state.tenant.key)}`;
  return (
    <CallDetailsPage
      onSelectDefinition={() => {
        if (!state.definition) return;
        window.history.pushState(
          {},
          "",
          `#${tenantPath}/definitions/${encodeURIComponent(state.definition.id)}`,
        );
      }}
      onSelectTenant={() => window.history.pushState({}, "", `#${tenantPath}`)}
      onSelectTenants={() => window.history.pushState({}, "", "#/admin")}
      state={state}
      theme={theme}
    />
  );
}
