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
  credentialName: string | null;
  updatedAt: string;
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
  truncated?: boolean;
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
