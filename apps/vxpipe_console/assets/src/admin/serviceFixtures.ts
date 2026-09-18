import type {
  CredentialDraft,
  ServiceInventoryItem,
  TenantServicesPageState,
} from "./serviceTypes";
import { demoTenant } from "./definitionFixtures";

export const services: ServiceInventoryItem[] = [
  {
    id: "google-primary",
    name: "Google",
    provider: "google",
    credentialName: "primary",
    updatedAt: "2026-09-17T03:00:00.000Z",
  },
  {
    id: "zenmux-fallback",
    name: "Zenmux",
    provider: "zenmux",
    credentialName: null,
    updatedAt: "2026-09-16T11:20:00.000Z",
  },
  {
    id: "deepgram-realtime",
    name: "Deepgram",
    provider: "deepgram",
    credentialName: "realtime",
    updatedAt: "2026-09-15T09:45:00.000Z",
  },
  {
    id: "telnyx-primary",
    name: "Telnyx",
    provider: "telnyx",
    credentialName: "primary",
    updatedAt: "2026-09-14T16:10:00.000Z",
  },
  {
    id: "twilio-backup",
    name: "Twilio",
    provider: "twilio",
    credentialName: "backup",
    updatedAt: "2026-09-12T07:30:00.000Z",
  },
];

export type ServiceFixtureScenario =
  | "populated"
  | "loading"
  | "empty"
  | "partial"
  | "unavailable"
  | "long-content"
  | "validation-error"
  | "submission-pending"
  | "save-failure"
  | "duplicate-conflict"
  | "save-success";

export function serviceFixture(
  scenario: ServiceFixtureScenario,
): TenantServicesPageState {
  const setup = { open: false, status: "idle" as const, resultVersion: 0 };
  switch (scenario) {
    case "loading":
      return { status: "loading", tenant: demoTenant, setup };
    case "empty":
      return { status: "ready", tenant: demoTenant, setup, services: [] };
    case "partial":
      return {
        status: "ready",
        tenant: demoTenant,
        setup,
        services,
        truncated: true,
      };
    case "unavailable":
      return {
        status: "unavailable",
        tenant: demoTenant,
        setup,
        message: "Services could not be loaded. Try again after storage is available.",
      };
    case "long-content":
      return {
        status: "ready",
        tenant: {
          key: "tn_international_customer_experience_operations_southeast_asia_2026",
          name: "International customer experience and delivery operations",
        },
        setup,
        services: [
          {
            ...services[3],
            id: "telnyx-long",
            name: "International priority outbound voice operations and exception handling",
            credentialName: `primary_${"credential_".repeat(10)}binding`,
            updatedAt: "2026-09-18T02:15:00.000Z",
          },
          ...services.slice(0, 2),
        ],
      };
    case "validation-error":
      return { status: "ready", tenant: demoTenant, services, setup: { open: true, status: "validation", resultVersion: 0, message: "Enter a credential name and every required credential field." } };
    case "submission-pending":
      return { status: "ready", tenant: demoTenant, services, setup: { open: true, status: "submitting", resultVersion: 0 } };
    case "save-failure":
      return {
        status: "ready",
        tenant: demoTenant,
        services,
        setup: { open: true, status: "error", resultVersion: 0, message: "Credential could not be stored." },
      };
    case "duplicate-conflict":
      return {
        status: "ready",
        tenant: demoTenant,
        services,
        setup: { open: true, status: "conflict", resultVersion: 0, message: "A credential with this provider and name already exists." },
      };
    case "save-success":
      return { status: "ready", tenant: demoTenant, services, setup: { open: false, status: "success", resultVersion: 1 } };
    case "populated":
      return { status: "ready", tenant: demoTenant, setup, services };
  }
}

export function applyCredentialCreation(
  state: TenantServicesPageState,
  draft: CredentialDraft,
): TenantServicesPageState {
  if (state.status !== "ready") return state;
  const duplicate = state.services.some(
    (service) =>
      service.provider === draft.provider && service.credentialName === draft.name,
  );
  if (duplicate) {
    return {
      ...state,
      setup: {
        open: true,
        status: "conflict",
        resultVersion: state.setup.resultVersion + 1,
        message: "A credential with this provider and name already exists.",
      },
    };
  }

  return {
    ...state,
    setup: {
      open: false,
      status: "success",
      resultVersion: state.setup.resultVersion + 1,
    },
    services: [
      ...state.services,
      {
        id: `${draft.provider}-${draft.name}`,
        name: draft.name,
        provider: draft.provider,
        credentialName: draft.name,
        updatedAt: new Date().toISOString(),
      },
    ],
  };
}
