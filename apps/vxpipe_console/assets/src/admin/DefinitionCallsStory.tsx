import { useState } from "react";

import { callFixture, type CallFixtureScenario } from "./callFixtures";
import { DefinitionCallsPage } from "./DefinitionCallsPage";

function shiftTimestamp(value: string, days: number): string;
function shiftTimestamp(value: string | null, days: number): string | null;
function shiftTimestamp(value: string | null, days: number): string | null {
  if (!value) return null;

  const timestamp = new Date(value);
  timestamp.setUTCDate(timestamp.getUTCDate() + days);
  return timestamp.toISOString();
}

export function DefinitionCallsStory({
  scenario,
  theme,
}: {
  scenario: CallFixtureScenario;
  theme: "dark" | "light";
}) {
  const [page, setPage] = useState(1);
  const baseState = callFixture(scenario);
  const state =
    scenario === "paginated" && baseState.status === "ready" && page > 1
      ? {
          ...baseState,
          calls: baseState.calls.map((call, index) => ({
            ...call,
            id: `${call.id.slice(0, -2)}${page}${index}`,
            createdAt: shiftTimestamp(call.createdAt, -28 * (page - 1)),
            startedAt: shiftTimestamp(call.startedAt, -28 * (page - 1)),
            endedAt: shiftTimestamp(call.endedAt, -28 * (page - 1)),
          })),
          pagination: {
            label: page === 2 ? "5–8 of 12" : "9–12 of 12",
            hasPrevious: true,
            hasNext: page < 3,
          },
        }
      : baseState;

  return (
    <DefinitionCallsPage
      onNextPage={() => setPage((current) => Math.min(3, current + 1))}
      onPreviousPage={() => setPage((current) => Math.max(1, current - 1))}
      onSelectCall={(callId) => {
        window.history.pushState(
          { callId },
          "",
          `#/admin/tenants/${encodeURIComponent(state.tenant.key)}/calls/${encodeURIComponent(callId)}`,
        );
      }}
      onSelectTenant={() => {
        window.history.pushState(
          { tenantKey: state.tenant.key },
          "",
          `#/admin/tenants/${encodeURIComponent(state.tenant.key)}`,
        );
      }}
      onSelectTenants={() => window.history.pushState({}, "", "#/admin")}
      state={state}
      theme={theme}
    />
  );
}
