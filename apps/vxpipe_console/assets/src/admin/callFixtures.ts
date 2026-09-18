import type {
  CallDirectoryItem,
  CallSummary,
  CallSpecCallsPageState,
  CallSpecContext,
} from "./callTypes";
import { callSpecs, demoTenant } from "./callSpecFixtures";

export const demoCallSpec: CallSpecContext = {
  id: callSpecs[0].id,
  name: callSpecs[0].name,
  latestRevision: callSpecs[0].latestRevision,
  publishedRevision: callSpecs[0].publishedRevision,
};

export const calls: CallSummary[] = [
  {
    id: "018f27cb-6f87-7d1c-a61f-8873cb667342",
    callSpecId: callSpecs[0].id,
    callSpecName: callSpecs[0].name,
    callSpecRevision: 3,
    state: "running",
    createdAt: "2026-09-17T02:20:00.000Z",
    startedAt: "2026-09-17T02:20:03.000Z",
    endedAt: null,
    terminalReason: null,
    archiveState: "unconfirmed",
  },
  {
    id: "018f27a2-51d5-77c9-a44f-e5c648bf8495",
    callSpecId: callSpecs[0].id,
    callSpecName: callSpecs[0].name,
    callSpecRevision: 2,
    state: "ended",
    createdAt: "2026-09-16T08:00:00.000Z",
    startedAt: "2026-09-16T08:00:02.000Z",
    endedAt: "2026-09-16T08:01:32.000Z",
    terminalReason: null,
    archiveState: "complete",
  },
  {
    id: "018f2791-f803-781c-9e96-35cc46d612cc",
    callSpecId: callSpecs[0].id,
    callSpecName: callSpecs[0].name,
    callSpecRevision: 4,
    state: "failed",
    createdAt: "2026-09-16T06:10:00.000Z",
    startedAt: null,
    endedAt: "2026-09-16T06:10:01.000Z",
    terminalReason: "session_start_failed",
    archiveState: "incomplete",
  },
  {
    id: "018f271e-4f94-7209-a69c-3df2d1523a3f",
    callSpecId: callSpecs[0].id,
    callSpecName: callSpecs[0].name,
    callSpecRevision: 3,
    state: "admitting",
    createdAt: "2026-09-15T12:00:00.000Z",
    startedAt: null,
    endedAt: null,
    terminalReason: null,
    archiveState: "unconfirmed",
  },
  {
    id: "018f2708-76d2-72f5-885c-d2d62a8a8ea1",
    callSpecId: callSpecs[0].id,
    callSpecName: callSpecs[0].name,
    callSpecRevision: 1,
    state: "prepared",
    createdAt: "2026-09-15T09:30:00.000Z",
    startedAt: null,
    endedAt: null,
    terminalReason: null,
    archiveState: "unconfirmed",
  },
];

const callSpecCalls: Record<string, CallSummary[]> = {
  [callSpecs[0].id]: calls,
  [callSpecs[1].id]: [
    {
      ...calls[1],
      id: "018f26f2-3bd6-73cd-b778-03150883006a",
      callSpecId: callSpecs[1].id,
      callSpecName: callSpecs[1].name,
      callSpecRevision: 2,
    },
    {
      ...calls[4],
      id: "018f26d9-1f04-7e4e-81c9-362cbab1d5f8",
      callSpecId: callSpecs[1].id,
      callSpecName: callSpecs[1].name,
      callSpecRevision: 1,
    },
  ],
  [callSpecs[2].id]: [
    {
      ...calls[4],
      id: "018f26a1-76e8-74f0-bc09-f65a2f7e3002",
      callSpecId: callSpecs[2].id,
      callSpecName: callSpecs[2].name,
      callSpecRevision: 1,
    },
  ],
  [callSpecs[3].id]: [
    {
      ...calls[1],
      id: "018f2677-b50a-75d7-9267-bd72827f4aa2",
      callSpecId: callSpecs[3].id,
      callSpecName: callSpecs[3].name,
      callSpecRevision: 7,
    },
  ],
};

function callSpecContext(callSpecId: string): CallSpecContext | null {
  const callSpec = callSpecs.find(
    (candidate) => candidate.id === callSpecId,
  );

  return callSpec
    ? {
        id: callSpec.id,
        name: callSpec.name,
        latestRevision: callSpec.latestRevision,
        publishedRevision: callSpec.publishedRevision,
      }
    : null;
}

function directoryItem(call: CallSummary): CallDirectoryItem {
  return {
    id: call.id,
    callSpecId: call.callSpecId,
    callSpecName: call.callSpecName,
    callSpecRevision: call.callSpecRevision,
    state:
      call.state === "ended" || call.state === "failed" ? "ended" : "ongoing",
    createdAt: call.createdAt,
  };
}

export function callsForCallSpec(callSpecId: string): CallDirectoryItem[] {
  return (callSpecCalls[callSpecId] ?? []).map(directoryItem);
}

export function callsForTenant(): CallDirectoryItem[] {
  return Object.values(callSpecCalls)
    .flat()
    .map(directoryItem)
    .sort(
      (left, right) => Date.parse(right.createdAt) - Date.parse(left.createdAt),
    );
}

export function callContext(callId: string): {
  callSpec: CallSpecContext;
  calls: CallSummary[];
} | null {
  for (const [callSpecId, callSpecCallList] of Object.entries(
    callSpecCalls,
  )) {
    if (callSpecCallList.some((call) => call.id === callId)) {
      const callSpec = callSpecContext(callSpecId);
      return callSpec ? { callSpec, calls: callSpecCallList } : null;
    }
  }

  return null;
}

export type CallFixtureScenario =
  | "populated"
  | "loading"
  | "empty"
  | "filtered"
  | "no-filter-matches"
  | "unknown-filter"
  | "unavailable"
  | "truncated-options"
  | "long-content"
  | "paginated";

export function callFixture(
  scenario: CallFixtureScenario,
): CallSpecCallsPageState {
  const context = {
    tenant: demoTenant,
    callSpecs: callSpecs.map(({ id, name }) => ({ id, name })),
    selectedCallSpecId: null,
  };
  switch (scenario) {
    case "loading":
      return { status: "loading", ...context };
    case "empty":
      return { status: "ready", ...context, calls: [], pagination: null };
    case "filtered":
      return {
        status: "ready",
        ...context,
        selectedCallSpecId: callSpecs[1].id,
        calls: callsForCallSpec(callSpecs[1].id),
        pagination: null,
      };
    case "no-filter-matches":
      return {
        status: "ready",
        ...context,
        selectedCallSpecId: callSpecs[1].id,
        calls: [],
        pagination: null,
      };
    case "unknown-filter":
      return {
        status: "ready",
        ...context,
        selectedCallSpecId: "removed-call-spec",
        calls: [],
        pagination: null,
      };
    case "unavailable":
      return {
        status: "unavailable",
        ...context,
        message:
          "Calls could not be loaded. Try again after storage is available.",
      };
    case "truncated-options":
      return {
        status: "ready",
        ...context,
        callSpecsTruncated: true,
        calls: callsForTenant(),
        pagination: null,
      };
    case "long-content":
      return {
        status: "ready",
        tenant: {
          key: "tn_international_customer_experience_operations_southeast_asia_2026",
          name: "International customer experience and delivery operations",
        },
        callSpecs: [
          {
            id: "international-priority-delivery-rescheduling-and-exception-resolution",
            name: "International priority delivery rescheduling and exception resolution",
          },
        ],
        selectedCallSpecId: null,
        calls: callsForTenant().slice(0, 4),
        pagination: null,
      };
    case "paginated":
      return {
        status: "ready",
        ...context,
        calls: callsForTenant()
          .slice(0, 4)
          .map((call) => ({
            ...call,
            callSpecId:
              "international-priority-delivery-rescheduling-and-exception-resolution",
            callSpecName:
              "International priority delivery rescheduling and exception resolution",
          })),
        pagination: {
          label: "1–4 of 12",
          hasPrevious: false,
          hasNext: true,
        },
      };
    case "populated":
      return {
        status: "ready",
        ...context,
        calls: callsForTenant(),
        pagination: {
          label: "1–9 of 27",
          hasPrevious: false,
          hasNext: true,
        },
      };
  }
}
