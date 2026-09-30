import type { TenantContext } from "./callSpecTypes";

export type CredentialField =
  | "apiKey"
  | "publicKey"
  | "accountSid"
  | "authToken";

export type ServiceProvider =
  | "cartesia"
  | "elevenlabs"
  | "rime"
  | "google"
  | "openai"
  | "vertex_ai"
  | "deepseek"
  | "openrouter"
  | "fireworks"
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
  lastValidatedAt: string | null;
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
  values:
    | { apiKey: string; publicKey?: string }
    | { accountSid: string; authToken: string };
};

export type CredentialTestResult =
  | { status: "valid" }
  | { status: "unsupported" | "error"; message: string };

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
