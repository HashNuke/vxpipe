import type { TenantContext } from "./definitionTypes";

export type ServiceProvider =
  | "google"
  | "vertex_ai"
  | "zenmux"
  | "deepgram"
  | "telnyx"
  | "twilio";

export type ServiceInventoryItem = {
  id: string;
  credentialId: string;
  name: string;
  provider: ServiceProvider;
  credentialName: string | null;
  credentialPreview?: CredentialPreview[];
  updatedAt: string;
};

export type CredentialPreview =
  | { label: string; format: "last_four"; lastFour: string }
  | { label: string; format: "masked" };

export type CredentialSetupStatus =
  | "idle"
  | "validation"
  | "submitting"
  | "error"
  | "conflict"
  | "success";

export type CredentialDraft = {
  provider: ServiceProvider;
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
