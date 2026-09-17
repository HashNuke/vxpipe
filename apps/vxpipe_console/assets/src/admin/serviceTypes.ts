import type { TenantContext } from "./definitionTypes";

export type ServiceProvider =
  | "google"
  | "zenmux"
  | "deepgram"
  | "telnyx"
  | "twilio";

export type ServiceInventoryItem = {
  id: string;
  name: string;
  provider: ServiceProvider;
  capability: "Models" | "Speech" | "Telephony";
  credentialName: string | null;
  serviceStatus: "not-applicable" | "not-registered" | "registered";
  telephonyConfiguration: {
    providerConnectionId: string;
    outboundNumber: string | null;
  } | null;
};

export type CredentialSetupStatus =
  | "idle"
  | "validation"
  | "submitting"
  | "error"
  | "conflict"
  | "success";

export type CredentialDraft = {
  provider: ServiceProvider;
  name: string;
  values: { apiKey: string } | { accountSid: string; authToken: string };
};

type ServicesContext = {
  tenant: TenantContext;
  setup: {
    open: boolean;
    status: CredentialSetupStatus;
    resultVersion: number;
    message?: string;
  };
};

export type TenantServicesPageState = ServicesContext &
  (
    | { status: "loading" }
    | { status: "unavailable"; message: string }
    | { status: "ready"; services: ServiceInventoryItem[] }
  );
