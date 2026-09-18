import { useState } from "react";

import {
  callFixture,
  callsForCallSpec,
  type CallFixtureScenario,
} from "./callFixtures";
import { CallSpecCallsPage } from "./CallSpecCallsPage";
import { callDetailsStoryHref } from "./adminStoryHref";

function shiftTimestamp(value: string, days: number): string;
function shiftTimestamp(value: string | null, days: number): string | null;
function shiftTimestamp(value: string | null, days: number): string | null {
  if (!value) return null;

  const timestamp = new Date(value);
  timestamp.setUTCDate(timestamp.getUTCDate() + days);
  return timestamp.toISOString();
}

export function CallSpecCallsStory({
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
  const pagedScenario = scenario === "paginated" || scenario === "populated";
  const pagedState =
    pagedScenario && baseState.status === "ready" && page > 1
      ? {
          ...baseState,
          calls: baseState.calls.map((call, index) => ({
            ...call,
            id: `${call.id.slice(0, -2)}${page}${index}`,
            createdAt: shiftTimestamp(call.createdAt, -28 * (page - 1)),
          })),
          pagination: {
            label:
              scenario === "populated"
                ? page === 2
                  ? "10–18 of 27"
                  : "19–27 of 27"
                : page === 2
                  ? "5–8 of 12"
                  : "9–12 of 12",
            hasPrevious: true,
            hasNext: page < 3,
          },
        }
      : baseState;
  const selectedCallSpecId =
    selectedOverride === undefined
      ? pagedState.selectedCallSpecId
      : selectedOverride;
  const allCallsState = callFixture("populated");
  const selectedCalls =
    selectedOverride === undefined
      ? pagedState.status === "ready"
        ? pagedState.calls
        : []
      : selectedCallSpecId
        ? callsForCallSpec(selectedCallSpecId)
        : allCallsState.status === "ready"
          ? allCallsState.calls
          : [];
  const state =
    pagedState.status === "ready"
      ? {
          ...pagedState,
          selectedCallSpecId,
          calls: selectedCalls,
          pagination:
            selectedOverride === undefined ? pagedState.pagination : null,
        }
      : { ...pagedState, selectedCallSpecId };

  return (
    <CallSpecCallsPage
      onNextPage={() => setPage((current) => Math.min(3, current + 1))}
      onPreviousPage={() => setPage((current) => Math.max(1, current - 1))}
      onSelectCallSpec={(callSpecId) => {
        setSelectedOverride(callSpecId);
        setPage(1);
        window.history.pushState(
          { callSpecId },
          "",
          `#/admin/tenants/${encodeURIComponent(state.tenant.key)}/calls${callSpecId ? `?call_spec_id=${encodeURIComponent(callSpecId)}` : ""}`,
        );
      }}
      callHref={(callId) =>
        callDetailsStoryHref(state.tenant.key, callId, theme)
      }
      onSelectTenant={() => {
        window.history.pushState(
          { tenantKey: state.tenant.key },
          "",
          `#/admin/tenants/${encodeURIComponent(state.tenant.key)}/call-specs`,
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
