import { useState } from "react";

import { tenantFixture, type TenantFixtureScenario } from "./tenantFixtures";
import { TenantsPage } from "./TenantsPage";

export function TenantsStory({
  scenario,
  theme,
}: {
  scenario: TenantFixtureScenario;
  theme: "dark" | "light";
}) {
  const [page, setPage] = useState(1);
  const baseState = tenantFixture(scenario);
  const state =
    scenario === "paginated" && baseState.status === "ready" && page > 1
      ? {
          ...baseState,
          tenants: baseState.tenants.map((tenant, index) => ({
            ...tenant,
            key: `${tenant.key}_p${page}`,
            name: `${tenant.name} · page ${page}`,
            createdAt: `2026-07-${String(24 - page * 4 - index).padStart(2, "0")}T09:00:00.000Z`,
          })),
          pagination: {
            label: page === 2 ? "5–8 of 12" : "9–12 of 12",
            hasPrevious: true,
            hasNext: page < 3,
          },
        }
      : baseState;

  return (
    <TenantsPage
      onNextPage={() => setPage((current) => Math.min(3, current + 1))}
      onPreviousPage={() => setPage((current) => Math.max(1, current - 1))}
      onSelectTenant={(tenantKey) => {
        window.history.pushState(
          { tenantKey },
          "",
          `#/admin/tenants/${encodeURIComponent(tenantKey)}`,
        );
      }}
      state={state}
      theme={theme}
    />
  );
}
