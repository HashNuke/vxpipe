import { useEffect, useState, type ReactNode } from "react";

import { Button } from "./Button";
import {
  ApiKeyCredentialFields,
  credentialInputClass,
} from "./credentials/ApiKeyCredentialFields";
import { TelnyxCredentialFields } from "./credentials/TelnyxCredentialFields";
import { TwilioCredentialFields } from "./credentials/TwilioCredentialFields";
import type {
  CredentialDraft,
  CredentialField,
  CredentialSetupStatus,
  CredentialTestResult,
  ServiceProvider,
} from "./serviceTypes";
import { validateCredentialDraft } from "./validateCredentialDraft";
import { setupProviders } from "./setupCatalog";

const providers = setupProviders.map((provider) => ({
  value: provider.id,
  label: provider.name,
}));
const apiKeyProviders: ReadonlySet<ServiceProvider> = new Set([
  "cartesia",
  "elevenlabs",
  "deepgram",
  "google",
  "openai",
  "rime",
  "zenmux",
  "deepseek",
  "openrouter",
  "fireworks",
]);
const credentialTestUnavailableProviders: ReadonlySet<ServiceProvider> = new Set([
  "fireworks",
  "cartesia",
  "elevenlabs",
]);

export function ServiceCredentialForm({
  initialProvider = "google",
  providerLocked = false,
  showCancel = true,
  showProvider = true,
  showTelnyxPublicKey = false,
  status,
  submitLabel = "Save",
  submittingLabel = "Saving…",
  message,
  onCancel,
  onSubmit,
  onTest,
  beforeActions,
  savedFields = [],
}: {
  initialProvider?: ServiceProvider;
  providerLocked?: boolean;
  showCancel?: boolean;
  showProvider?: boolean;
  showTelnyxPublicKey?: boolean;
  status: CredentialSetupStatus;
  submitLabel?: string;
  submittingLabel?: string;
  message?: string;
  onCancel: () => void;
  onSubmit: (draft: CredentialDraft) => void;
  onTest?: (draft: CredentialDraft) => Promise<CredentialTestResult>;
  beforeActions?: ReactNode;
  savedFields?: CredentialField[];
}) {
  const [provider, setProvider] = useState<ServiceProvider>(initialProvider);
  const [apiKey, setApiKey] = useState("");
  const [publicKey, setPublicKey] = useState("");
  const supportedProvider =
    apiKeyProviders.has(provider) || provider === "telnyx" || provider === "twilio";
  const supportsCredentialTest = supportedProvider && !credentialTestUnavailableProviders.has(provider);
  const includePublicKey = provider === "telnyx" && showTelnyxPublicKey;
  const [accountSid, setAccountSid] = useState("");
  const [authToken, setAuthToken] = useState("");
  const [validationMessage, setValidationMessage] = useState<string | null>(
    null,
  );
  const [testResult, setTestResult] = useState<
    CredentialTestResult | { status: "testing" } | null
  >(null);

  function clearSecrets() {
    setApiKey("");
    setPublicKey("");
    setAccountSid("");
    setAuthToken("");
  }

  function clearTestResult() {
    setTestResult(null);
  }

  function draft(): CredentialDraft {
    return {
      provider,
      values:
        provider === "twilio"
          ? { accountSid, authToken }
          : {
              apiKey,
              ...(includePublicKey && publicKey.trim()
                ? { publicKey: publicKey.trim() }
                : {}),
            },
    };
  }

  function locallyValidDraft() {
    if (!supportedProvider) return null;
    const nextDraft = draft();
    const nextValidationMessage = validateCredentialDraft(nextDraft);
    setValidationMessage(nextValidationMessage);
    return nextValidationMessage ? null : nextDraft;
  }

  async function testCredentials() {
    const nextDraft = locallyValidDraft();
    if (!nextDraft || !onTest || !supportsCredentialTest) return;

    setTestResult({ status: "testing" });
    try {
      setTestResult(await onTest(nextDraft));
    } catch {
      setTestResult({
        status: "error",
        message: "Credentials could not be tested. Check the connection and try again.",
      });
    }
  }

  useEffect(() => {
    setProvider(initialProvider);
    clearSecrets();
    clearTestResult();
  }, [initialProvider]);

  useEffect(() => {
    if (
      status === "success" ||
      status === "conflict" ||
      status === "validation" ||
      status === "error"
    ) {
      clearSecrets();
      clearTestResult();
    }
  }, [status]);

  const saving = status === "submitting";
  const testing = testResult?.status === "testing";
  const pending = saving || testing;
  const savedPlaceholder = (field: CredentialField) =>
    provider === initialProvider && savedFields.includes(field)
      ? "••••••••"
      : undefined;
  return (
    <form
      aria-label="Credential setup"
      className="grid gap-4"
      onSubmit={(event) => {
        event.preventDefault();
        const nextDraft = locallyValidDraft();
        if (nextDraft) onSubmit(nextDraft);
      }}
    >
      {showProvider ? (
        <label className="grid gap-1.5 text-sm font-semibold">
          Provider
          <select
            className={credentialInputClass}
            disabled={pending || providerLocked}
            onChange={(event) => {
              setProvider(event.target.value as ServiceProvider);
              clearSecrets();
              clearTestResult();
            }}
            value={provider}
          >
            {providers.map((candidate) => (
              <option key={candidate.value} value={candidate.value}>
                {candidate.label}
              </option>
            ))}
          </select>
        </label>
      ) : null}
      {!supportedProvider ? (
        <p className="text-sm text-[var(--admin-red)]" role="alert">
          Credential setup is unavailable for this provider.
        </p>
      ) : provider === "twilio" ? (
        <TwilioCredentialFields
          accountSid={accountSid}
          onAccountSidChange={(value) => {
            setAccountSid(value);
            clearTestResult();
          }}
          accountSidPlaceholder={savedPlaceholder("accountSid")}
          authToken={authToken}
          onAuthTokenChange={(value) => {
            setAuthToken(value);
            clearTestResult();
          }}
          authTokenPlaceholder={savedPlaceholder("authToken")}
          disabled={pending}
        />
      ) : provider === "telnyx" ? (
        <TelnyxCredentialFields
          value={apiKey}
          onChange={(value) => {
            setApiKey(value);
            clearTestResult();
          }}
          disabled={pending}
          placeholder={savedPlaceholder("apiKey")}
          showPublicKey={includePublicKey}
          publicKey={publicKey}
          onPublicKeyChange={(value) => {
            setPublicKey(value);
            clearTestResult();
          }}
          publicKeyPlaceholder={savedPlaceholder("publicKey")}
          publicKeySaved={savedFields.includes("publicKey")}
        />
      ) : (
        <ApiKeyCredentialFields
          value={apiKey}
          onChange={(value) => {
            setApiKey(value);
            clearTestResult();
          }}
          disabled={pending}
          placeholder={savedPlaceholder("apiKey")}
        />
      )}
      {validationMessage ? (
        <p className="text-sm text-[var(--admin-red)]" role="alert">
          {validationMessage}
        </p>
      ) : null}
      {message ? (
        <p className="text-sm text-[var(--admin-red)]" role="alert">
          {message}
        </p>
      ) : null}
      {testResult?.status === "valid" ? (
        <p className="text-sm text-[var(--admin-green)]" role="status">
          Credentials tested successfully.
        </p>
      ) : null}
      {testResult?.status === "unsupported" ? (
        <p className="text-sm text-[var(--admin-muted)]" role="status">
          {testResult.message}
        </p>
      ) : null}
      {testResult?.status === "error" ? (
        <p className="text-sm text-[var(--admin-red)]" role="alert">
          {testResult.message}
        </p>
      ) : null}
      {status === "success" ? (
        <p className="text-sm text-[var(--admin-green)]" role="status">
          Credential stored.
        </p>
      ) : null}
      {credentialTestUnavailableProviders.has(provider) ? (
        <p className="text-sm text-[var(--admin-muted)]">
          Credential testing is unavailable for this provider. You can save its API key and verify it with a call.
        </p>
      ) : null}
      {beforeActions}
      <div className="setup-credential-actions" role="group" aria-label="Credential actions">
        {showCancel ? (
          <Button
            disabled={pending}
            onClick={() => {
              clearSecrets();
              onCancel();
            }}
            type="button"
            variant="ghost"
          >
            Cancel
          </Button>
        ) : null}
        <Button
          aria-label={testing ? "Testing credentials" : "Test credentials"}
          disabled={pending || !onTest || !supportsCredentialTest}
          onClick={() => void testCredentials()}
          type="button"
          variant="ghost"
        >
          {testing ? (
            "Testing…"
          ) : (
            <>
              <span className="setup-test-full">Test credentials</span>
              <span aria-hidden="true" className="setup-test-short">Test</span>
            </>
          )}
        </Button>
        <Button disabled={pending || !supportedProvider} type="submit">
          {saving ? submittingLabel : submitLabel}
        </Button>
      </div>
    </form>
  );
}
