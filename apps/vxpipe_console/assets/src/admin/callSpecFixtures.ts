import type {
  CallSpecSummary,
  TenantContext,
  TenantCallSpecsPageState,
} from "./callSpecTypes";

export const demoTenant: TenantContext = {
  key: "tn_demo_01",
  name: "Demo workspace",
};

export const callSpecs: CallSpecSummary[] = [
  {
    id: "delivery-rescheduling",
    name: "Delivery rescheduling",
    latestRevision: 4,
    publishedRevision: 3,
    callCount: 5,
    updatedAt: "2026-09-16T08:40:00.000Z",
  },
  {
    id: "appointment-reminders",
    name: "Appointment reminders",
    latestRevision: 2,
    publishedRevision: 2,
    callCount: 2,
    updatedAt: "2026-09-15T10:20:00.000Z",
  },
  {
    id: "returns-intake",
    name: null,
    latestRevision: 1,
    publishedRevision: null,
    callCount: 1,
    updatedAt: "2026-09-14T03:15:00.000Z",
  },
  {
    id: "after-hours-triage",
    name: "After-hours triage",
    latestRevision: 7,
    publishedRevision: 7,
    callCount: 1,
    updatedAt: "2026-09-11T17:05:00.000Z",
  },
];

export type CallSpecFixtureScenario =
  | "populated"
  | "loading"
  | "empty"
  | "unavailable"
  | "long-content"
  | "paginated";

export function callSpecFixture(
  scenario: CallSpecFixtureScenario,
): TenantCallSpecsPageState {
  switch (scenario) {
    case "loading":
      return { status: "loading", tenant: demoTenant };
    case "empty":
      return {
        status: "ready",
        tenant: demoTenant,
        callSpecs: [],
        pagination: null,
      };
    case "unavailable":
      return {
        status: "unavailable",
        tenant: demoTenant,
        message:
          "Call specs could not be loaded. Try again after storage is available.",
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
            latestRevision: 128,
            publishedRevision: 127,
            callCount: 12_480,
            updatedAt: "2026-09-16T08:40:00.000Z",
          },
          ...callSpecs.slice(0, 2),
        ],
        pagination: null,
      };
    case "paginated":
      return {
        status: "ready",
        tenant: demoTenant,
        callSpecs,
        pagination: {
          label: "1–4 of 12",
          hasPrevious: false,
          hasNext: true,
        },
      };
    case "populated":
      return {
        status: "ready",
        tenant: demoTenant,
        callSpecs,
        pagination: null,
      };
  }
}
