import type { CredentialDraft, CredentialTestResult } from "./serviceTypes";

type Fetch = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Promise<Response>;

export function credentialRequest(draft: CredentialDraft, name?: string) {
  const values =
    "apiKey" in draft.values
      ? {
          api_key: draft.values.apiKey,
          ...(draft.provider === "telnyx" && draft.values.publicKey
            ? { public_key: draft.values.publicKey }
            : {}),
        }
      : {
          account_sid: draft.values.accountSid,
          auth_token: draft.values.authToken,
        };

  return {
    provider: draft.provider,
    ...(name ? { name } : {}),
    values,
  };
}

export async function testCredentialRequest(
  url: string,
  draft: CredentialDraft,
  name: string | undefined,
  csrfToken: string,
  fetchImpl: Fetch,
  onSessionExpired: () => void,
  signal?: AbortSignal,
): Promise<CredentialTestResult> {
  try {
    const response = await fetchImpl(url, {
      method: "POST",
      credentials: "same-origin",
      signal,
      headers: {
        accept: "application/json",
        "content-type": "application/json",
        "x-csrf-token": csrfToken,
      },
      body: JSON.stringify(credentialRequest(draft, name)),
    });

    if (response.status === 401) {
      onSessionExpired();
      return { status: "error", message: "Your session expired. Sign in again." };
    }
    if (response.status === 501) {
      return {
        status: "unsupported",
        message:
          "Credential testing is not available for this service. You can still save it.",
      };
    }
    if (response.status === 422) {
      return {
        status: "error",
        message: "The credentials were rejected. Check them and try again.",
      };
    }
    if (!response.ok) throw new Error("Credential test unavailable");

    const result: unknown = await response.json();
    if (!validCredentialTestResponse(result)) {
      return {
        status: "error",
        message: "The credential test returned an invalid response.",
      };
    }
    return { status: "valid" };
  } catch {
    return {
      status: "error",
      message:
        "Credentials could not be tested. Check the connection and try again.",
    };
  }
}

function validCredentialTestResponse(value: unknown) {
  return (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value) &&
    Object.keys(value).length === 1 &&
    "status" in value &&
    value.status === "valid"
  );
}
