import type {
  CallSummary,
  DefinitionCallsPageState,
  DefinitionContext,
} from "./callTypes";
import { definitions, demoTenant } from "./definitionFixtures";

export const demoDefinition: DefinitionContext = {
  id: definitions[0].id,
  name: definitions[0].name,
  latestRevision: definitions[0].latestRevision,
  publishedRevision: definitions[0].publishedRevision,
};

export const calls: CallSummary[] = [
  {
    id: "018f27cb-6f87-7d1c-a61f-8873cb667342",
    definitionRevision: 3,
    state: "running",
    createdAt: "2026-09-17T02:20:00.000Z",
    startedAt: "2026-09-17T02:20:03.000Z",
    endedAt: null,
    terminalReason: null,
    archiveState: "unconfirmed",
  },
  {
    id: "018f27a2-51d5-77c9-a44f-e5c648bf8495",
    definitionRevision: 2,
    state: "ended",
    createdAt: "2026-09-16T08:00:00.000Z",
    startedAt: "2026-09-16T08:00:02.000Z",
    endedAt: "2026-09-16T08:01:32.000Z",
    terminalReason: null,
    archiveState: "complete",
  },
  {
    id: "018f2791-f803-781c-9e96-35cc46d612cc",
    definitionRevision: 4,
    state: "failed",
    createdAt: "2026-09-16T06:10:00.000Z",
    startedAt: null,
    endedAt: "2026-09-16T06:10:01.000Z",
    terminalReason: "session_start_failed",
    archiveState: "incomplete",
  },
  {
    id: "018f271e-4f94-7209-a69c-3df2d1523a3f",
    definitionRevision: 3,
    state: "admitting",
    createdAt: "2026-09-15T12:00:00.000Z",
    startedAt: null,
    endedAt: null,
    terminalReason: null,
    archiveState: "unconfirmed",
  },
  {
    id: "018f2708-76d2-72f5-885c-d2d62a8a8ea1",
    definitionRevision: 1,
    state: "prepared",
    createdAt: "2026-09-15T09:30:00.000Z",
    startedAt: null,
    endedAt: null,
    terminalReason: null,
    archiveState: "unconfirmed",
  },
];

const definitionCalls: Record<string, CallSummary[]> = {
  [definitions[0].id]: calls,
  [definitions[1].id]: [
    {
      ...calls[1],
      id: "018f26f2-3bd6-73cd-b778-03150883006a",
      definitionRevision: 2,
    },
    {
      ...calls[4],
      id: "018f26d9-1f04-7e4e-81c9-362cbab1d5f8",
      definitionRevision: 1,
    },
  ],
  [definitions[2].id]: [
    {
      ...calls[4],
      id: "018f26a1-76e8-74f0-bc09-f65a2f7e3002",
      definitionRevision: 1,
    },
  ],
  [definitions[3].id]: [
    {
      ...calls[1],
      id: "018f2677-b50a-75d7-9267-bd72827f4aa2",
      definitionRevision: 7,
    },
  ],
};

function definitionContext(definitionId: string): DefinitionContext | null {
  const definition = definitions.find((candidate) => candidate.id === definitionId);

  return definition
    ? {
        id: definition.id,
        name: definition.name,
        latestRevision: definition.latestRevision,
        publishedRevision: definition.publishedRevision,
      }
    : null;
}

export function callsForDefinition(definitionId: string): CallSummary[] {
  return definitionCalls[definitionId] ?? [];
}

export function callContext(callId: string): {
  definition: DefinitionContext;
  calls: CallSummary[];
} | null {
  for (const [definitionId, definitionCallList] of Object.entries(
    definitionCalls,
  )) {
    if (definitionCallList.some((call) => call.id === callId)) {
      const definition = definitionContext(definitionId);
      return definition ? { definition, calls: definitionCallList } : null;
    }
  }

  return null;
}

export type CallFixtureScenario =
  | "populated"
  | "loading"
  | "empty"
  | "unavailable"
  | "long-content"
  | "paginated";

export function callFixture(scenario: CallFixtureScenario): DefinitionCallsPageState {
  const context = { tenant: demoTenant, definition: demoDefinition };
  switch (scenario) {
    case "loading":
      return { status: "loading", ...context };
    case "empty":
      return { status: "ready", ...context, calls: [], pagination: null };
    case "unavailable":
      return {
        status: "unavailable",
        ...context,
        message: "Calls could not be loaded. Try again after storage is available.",
      };
    case "long-content":
      return {
        status: "ready",
        tenant: {
          key: "tn_international_customer_experience_operations_southeast_asia_2026",
          name: "International customer experience and delivery operations",
        },
        definition: {
          id: "international-priority-delivery-rescheduling-and-exception-resolution",
          name: "International priority delivery rescheduling and exception resolution",
          latestRevision: 128,
          publishedRevision: 127,
        },
        calls: calls.slice(0, 4),
        pagination: null,
      };
    case "paginated":
      return {
        status: "ready",
        ...context,
        calls: calls.slice(0, 4),
        pagination: {
          label: "1–4 of 12",
          hasPrevious: false,
          hasNext: true,
        },
      };
    case "populated":
      return { status: "ready", ...context, calls, pagination: null };
  }
}
