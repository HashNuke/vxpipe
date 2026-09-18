import type { CredentialDraft, ServiceProvider } from "./serviceTypes";

const apiKeyPattern = /^[\x21-\x7E]+$/;
const twilioAccountSidPattern = /^AC[0-9a-fA-F]{32}$/;

function byteLength(value: string) {
  return new TextEncoder().encode(value).length;
}

function maximumApiKeyBytes(provider: ServiceProvider) {
  return provider === "telnyx" ? 4_096 : 8_192;
}

export function validateCredentialDraft(draft: CredentialDraft): string | null {
  if ("apiKey" in draft.values) {
    if (
      byteLength(draft.values.apiKey) > maximumApiKeyBytes(draft.provider) ||
      !apiKeyPattern.test(draft.values.apiKey)
    ) {
      return "Enter a valid API key without spaces or line breaks.";
    }
    return null;
  }

  if (
    !twilioAccountSidPattern.test(draft.values.accountSid) ||
    byteLength(draft.values.authToken) < 1 ||
    byteLength(draft.values.authToken) > 4_096
  ) {
    return "Enter a valid Twilio Account SID and auth token.";
  }

  return null;
}
