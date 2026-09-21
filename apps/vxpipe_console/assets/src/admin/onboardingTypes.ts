import type {
  CredentialDraft,
  CredentialTestResult,
  ServiceProvider,
} from "./serviceTypes";

export type OnboardingProviderStatus =
  | "needs_credentials"
  | "validating"
  | "valid"
  | "invalid"
  | "unavailable";

export type OnboardingProvider = {
  provider: ServiceProvider;
  label: string;
  services: string[];
  status: OnboardingProviderStatus;
  lastValidatedAt?: string | null;
  message?: string;
  source?: "platform" | "tenant";
};

export type OnboardingSample = {
  id: string;
  name: string;
  status: "available" | "installed" | "failed";
};

export type OnboardingPageState = {
  tenant:
    | { status: "creating"; name: string }
    | { status: "ready"; key: string; name: string }
    | { status: "unavailable"; name: string; message: string };
  providers: OnboardingProvider[];
  samples: {
    status: "blocked" | "ready" | "loading" | "complete" | "error";
    items: OnboardingSample[];
    message?: string;
  };
};

export type OnboardingCredentialSubmit = (draft: CredentialDraft) => void;
export type OnboardingCredentialTest = (
  draft: CredentialDraft,
) => Promise<CredentialTestResult>;
