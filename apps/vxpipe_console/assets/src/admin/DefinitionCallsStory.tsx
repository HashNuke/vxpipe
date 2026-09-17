import { useState } from "react";

import { callFixture, callsForDefinition, type CallFixtureScenario } from "./callFixtures";
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
  const [selectedOverride, setSelectedOverride] = useState<
    string | null | undefined
  >(undefined);
  const baseState = callFixture(scenario);
  const pagedState =
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
  const selectedDefinitionId =
    selectedOverride === undefined
      ? pagedState.selectedDefinitionId
      : selectedOverride;
  const allCallsState = callFixture("populated");
  const selectedCalls =
    selectedOverride === undefined
      ? pagedState.status === "ready"
        ? pagedState.calls
        : []
      : selectedDefinitionId
        ? callsForDefinition(selectedDefinitionId)
        : allCallsState.status === "ready"
          ? allCallsState.calls
          : [];
  const state =
    pagedState.status === "ready"
      ? {
          ...pagedState,
          selectedDefinitionId,
          calls: selectedCalls,
          pagination:
            selectedOverride === undefined ? pagedState.pagination : null,
        }
      : { ...pagedState, selectedDefinitionId };

  return (
    <DefinitionCallsPage
      onNextPage={() => setPage((current) => Math.min(3, current + 1))}
      onPreviousPage={() => setPage((current) => Math.max(1, current - 1))}
      onSelectDefinition={(definitionId) => {
        setSelectedOverride(definitionId);
        setPage(1);
        window.history.pushState(
          { definitionId },
          "",
          `#/admin/tenants/${encodeURIComponent(state.tenant.key)}/calls${definitionId ? `?definition_id=${encodeURIComponent(definitionId)}` : ""}`,
        );
      }}
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
          `#/admin/tenants/${encodeURIComponent(state.tenant.key)}/definitions`,
        );
      }}
      onSelectTenants={() => window.history.pushState({}, "", "#/admin")}
      onSelectWorkspace={(destination) =>
        window.history.pushState(
          { destination },
          "",
          `#/admin/tenants/${encodeURIComponent(state.tenant.key)}/${destination}`,
        )
      }
      state={state}
      theme={theme}
    />
  );
}
