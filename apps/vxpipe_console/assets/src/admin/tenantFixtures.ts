import type { TenantsPageState, TenantSummary } from "./tenantTypes";

const tenants: TenantSummary[] = [
  {
    key: "tn_demo_01",
    name: "Demo workspace",
    createdAt: "2026-09-14T09:30:00.000Z",
  },
  {
    key: "tn_courier_ops",
    name: "Courier operations",
    createdAt: "2026-08-29T15:12:00.000Z",
  },
  {
    key: "tn_clinic_north",
    name: "North clinic",
    createdAt: "2026-08-18T03:45:00.000Z",
  },
  {
    key: "tn_field_service",
    name: "Field service",
    createdAt: "2026-07-31T22:18:00.000Z",
  },
];

export type TenantFixtureScenario =
  | "populated"
  | "loading"
  | "empty"
  | "unavailable"
  | "long-content"
  | "paginated";

export function tenantFixture(scenario: TenantFixtureScenario): TenantsPageState {
  switch (scenario) {
    case "loading":
      return { status: "loading" };
    case "empty":
      return { status: "ready", tenants: [], pagination: null };
    case "unavailable":
      return {
        status: "unavailable",
        message: "Tenant data could not be loaded. Try again after storage is available.",
      };
    case "long-content":
      return {
        status: "ready",
        tenants: [
          {
            key: "tn_international_customer_experience_operations_southeast_asia_2026",
            name: "International customer experience and delivery operations",
            createdAt: "2026-09-01T13:24:00.000Z",
          },
          ...tenants.slice(0, 2),
        ],
        pagination: null,
      };
    case "paginated":
      return {
        status: "ready",
        tenants,
        pagination: {
          label: "1–4 of 12",
          hasPrevious: false,
          hasNext: true,
        },
      };
    case "populated":
      return {
        status: "ready",
        tenants,
        pagination: null,
      };
  }
}
