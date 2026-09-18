import { useState } from "react";

import {
  callSpecFixture,
  type CallSpecFixtureScenario,
} from "./callSpecFixtures";
import { TenantCallSpecsPage } from "./TenantCallSpecsPage";

export function TenantCallSpecsStory({
  scenario,
  theme,
}: {
  scenario: CallSpecFixtureScenario;
  theme: "dark" | "light";
}) {
  const [page, setPage] = useState(1);
  const baseState = callSpecFixture(scenario);
  const state =
    scenario === "paginated" && baseState.status === "ready" && page > 1
      ? {
          ...baseState,
          callSpecs: baseState.callSpecs.map((callSpec, index) => ({
            ...callSpec,
            id: `${callSpec.id}-p${page}`,
            name: `${callSpec.name ?? callSpec.id} · page ${page}`,
            updatedAt: `2026-08-${String(24 - page * 4 - index).padStart(2, "0")}T09:00:00.000Z`,
          })),
          pagination: {
            label: page === 2 ? "5–8 of 12" : "9–12 of 12",
            hasPrevious: true,
            hasNext: page < 3,
          },
        }
      : baseState;

  return (
    <TenantCallSpecsPage
      onNextPage={() => setPage((current) => Math.min(3, current + 1))}
      onPreviousPage={() => setPage((current) => Math.max(1, current - 1))}
      onSelectCallSpec={(callSpecId) => {
        window.history.pushState(
          { callSpecId },
          "",
          `#/admin/tenants/${encodeURIComponent(state.tenant.key)}/calls?call_spec_id=${encodeURIComponent(callSpecId)}`,
        );
      }}
      onSelectTenants={() => {
        window.history.pushState({}, "", "#/admin");
      }}
      onSelectWorkspace={(destination) => {
        window.history.pushState(
          { destination },
          "",
          `#/admin/tenants/${encodeURIComponent(state.tenant.key)}/${destination}`,
        );
      }}
      state={state}
      theme={theme}
    />
  );
}
