import { useState } from "react";

import {
  definitionFixture,
  type DefinitionFixtureScenario,
} from "./definitionFixtures";
import { TenantDefinitionsPage } from "./TenantDefinitionsPage";

export function TenantDefinitionsStory({
  scenario,
  theme,
}: {
  scenario: DefinitionFixtureScenario;
  theme: "dark" | "light";
}) {
  const [page, setPage] = useState(1);
  const baseState = definitionFixture(scenario);
  const state =
    scenario === "paginated" && baseState.status === "ready" && page > 1
      ? {
          ...baseState,
          definitions: baseState.definitions.map((definition, index) => ({
            ...definition,
            id: `${definition.id}-p${page}`,
            name: `${definition.name ?? definition.id} · page ${page}`,
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
    <TenantDefinitionsPage
      onNextPage={() => setPage((current) => Math.min(3, current + 1))}
      onPreviousPage={() => setPage((current) => Math.max(1, current - 1))}
      onSelectDefinition={(definitionId) => {
        window.history.pushState(
          { definitionId },
          "",
          `#/admin/tenants/${encodeURIComponent(state.tenant.key)}/definitions/${encodeURIComponent(definitionId)}`,
        );
      }}
      onSelectTenants={() => {
        window.history.pushState({}, "", "#/admin");
      }}
      state={state}
      theme={theme}
    />
  );
}
