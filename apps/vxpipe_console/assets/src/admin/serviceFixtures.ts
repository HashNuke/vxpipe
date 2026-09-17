import type {
  CredentialDraft,
  ServiceInventoryItem,
  TenantServicesPageState,
} from "./serviceTypes";
import { demoTenant } from "./definitionFixtures";

export const services: ServiceInventoryItem[] = [
  {
    id: "google-primary",
    name: "Primary Google models",
    provider: "google",
    capability: "Models",
    credentialName: "primary",
    serviceStatus: "not-applicable",
    telephonyConfiguration: null,
  },
  {
    id: "zenmux-fallback",
    name: "Zenmux fallback",
    provider: "zenmux",
    capability: "Models",
    credentialName: null,
    serviceStatus: "not-applicable",
    telephonyConfiguration: null,
  },
  {
    id: "deepgram-realtime",
    name: "Realtime transcription",
    provider: "deepgram",
    capability: "Speech",
    credentialName: "realtime",
    serviceStatus: "not-applicable",
    telephonyConfiguration: null,
  },
  {
    id: "telnyx-primary",
    name: "Primary voice service",
    provider: "telnyx",
    capability: "Telephony",
    credentialName: "primary",
    serviceStatus: "registered",
    telephonyConfiguration: {
      providerConnectionId: "connection-primary",
      outboundNumber: "+14155550100",
    },
  },
  {
    id: "twilio-backup",
    name: "Backup voice service",
    provider: "twilio",
    capability: "Telephony",
    credentialName: "backup",
    serviceStatus: "not-registered",
    telephonyConfiguration: null,
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
        services: services.map((service) =>
          service.serviceStatus === "not-registered"
            ? { ...service, serviceStatus: "unknown" as const }
            : service,
        ),
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
            telephonyConfiguration: {
              providerConnectionId:
                "connection-international-priority-voice-operations-southeast-asia",
              outboundNumber: "+14155550100",
            },
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

  const telephony = draft.provider === "telnyx" || draft.provider === "twilio";
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
        capability:
          draft.provider === "deepgram"
            ? "Speech"
            : telephony
              ? "Telephony"
              : "Models",
        credentialName: draft.name,
        serviceStatus: telephony ? "not-registered" : "not-applicable",
        telephonyConfiguration: null,
      },
    ],
  };
}
