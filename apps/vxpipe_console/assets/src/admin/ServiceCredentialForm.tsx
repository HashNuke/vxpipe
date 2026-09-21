import { useEffect, useId, useState, type ReactNode } from "react";

import { Button } from "./Button";
import type {
  CredentialDraft,
  CredentialField,
  CredentialSetupStatus,
  CredentialTestResult,
  ServiceProvider,
} from "./serviceTypes";
import { validateCredentialDraft } from "./validateCredentialDraft";

const providers: Array<{ value: ServiceProvider; label: string }> = [
  { value: "google", label: "Google AI Studio" },
  { value: "vertex_ai", label: "Google Vertex AI" },
  { value: "zenmux", label: "Zenmux" },
  { value: "deepgram", label: "Deepgram" },
  { value: "telnyx", label: "Telnyx" },
  { value: "twilio", label: "Twilio" },
];

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
  const inputId = useId();
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
    const nextDraft = draft();
    const nextValidationMessage = validateCredentialDraft(nextDraft);
    setValidationMessage(nextValidationMessage);
    return nextValidationMessage ? null : nextDraft;
  }

  async function testCredentials() {
    const nextDraft = locallyValidDraft();
    if (!nextDraft || !onTest) return;

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
  const fieldClass =
    "h-10 w-full rounded-sm border border-[var(--admin-line)] bg-[var(--admin-bg)] px-3 text-sm text-[var(--admin-ink)]";

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
            className={fieldClass}
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
      {provider === "twilio" ? (
        <>
          <label className="grid gap-1.5 text-sm font-semibold">
            Account SID
            <input
              className={fieldClass}
              disabled={pending}
              onChange={(event) => {
                setAccountSid(event.target.value);
                clearTestResult();
              }}
              placeholder={savedPlaceholder("accountSid")}
              type="password"
              value={accountSid}
            />
          </label>
          <label className="grid gap-1.5 text-sm font-semibold">
            Auth token
            <input
              className={fieldClass}
              disabled={pending}
              onChange={(event) => {
                setAuthToken(event.target.value);
                clearTestResult();
              }}
              placeholder={savedPlaceholder("authToken")}
              type="password"
              value={authToken}
            />
          </label>
        </>
      ) : (
        <>
          <div className="grid gap-1.5 text-sm">
            <label className="font-semibold" htmlFor={`${inputId}-api`}>
              API key
            </label>
            <input
              id={`${inputId}-api`}
              className={fieldClass}
              disabled={pending}
              onChange={(event) => {
                setApiKey(event.target.value);
                clearTestResult();
              }}
              placeholder={savedPlaceholder("apiKey")}
              type="password"
              value={apiKey}
            />
          </div>
          {includePublicKey ? (
            <div className="grid gap-1.5 text-sm">
              <label className="font-semibold" htmlFor={`${inputId}-public`}>
                Public key
              </label>
              <input
                id={`${inputId}-public`}
                aria-describedby={`${inputId}-public-hint`}
                className={fieldClass}
                disabled={pending}
                onChange={(event) => {
                  setPublicKey(event.target.value);
                  clearTestResult();
                }}
                placeholder={savedPlaceholder("publicKey")}
                spellCheck={false}
                type="text"
                value={publicKey}
              />
              <p
                id={`${inputId}-public-hint`}
                className="text-xs text-[var(--admin-muted)]"
              >
                Optional; Only required for Telephony services
                {savedFields.includes("publicKey")
                  ? ". Leave blank to remove the saved public key; phone calls will require a new key."
                  : ""}
              </p>
            </div>
          ) : null}
        </>
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
      {beforeActions}
      <div className="flex flex-wrap justify-end gap-2">
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
          disabled={pending || !onTest}
          onClick={() => void testCredentials()}
          type="button"
          variant="ghost"
        >
          {testing ? "Testing…" : "Test credentials"}
        </Button>
        <Button disabled={pending} type="submit">
          {saving ? submittingLabel : submitLabel}
        </Button>
      </div>
    </form>
  );
}
