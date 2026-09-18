import { useEffect, useId, useState } from "react";

import { Button } from "./Button";
import type {
  CredentialDraft,
  CredentialSetupStatus,
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
  submitLabel = "Save credential",
  submittingLabel = "Saving…",
  message,
  onCancel,
  onSubmit,
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

  function clearSecrets() {
    setApiKey("");
    setPublicKey("");
    setAccountSid("");
    setAuthToken("");
  }

  useEffect(() => {
    setProvider(initialProvider);
    clearSecrets();
  }, [initialProvider]);

  useEffect(() => {
    if (
      status === "success" ||
      status === "conflict" ||
      status === "validation" ||
      status === "error"
    ) {
      clearSecrets();
    }
  }, [status]);

  const pending = status === "submitting";
  const fieldClass =
    "h-10 w-full rounded-sm border border-[var(--admin-line)] bg-[var(--admin-bg)] px-3 text-sm text-[var(--admin-ink)]";

  return (
    <form
      aria-label="Credential setup"
      className="grid gap-4"
      onSubmit={(event) => {
        event.preventDefault();
        const draft: CredentialDraft = {
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
        const nextValidationMessage = validateCredentialDraft(draft);
        setValidationMessage(nextValidationMessage);
        if (!nextValidationMessage) onSubmit(draft);
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
              onChange={(event) => setAccountSid(event.target.value)}
              type="password"
              value={accountSid}
            />
          </label>
          <label className="grid gap-1.5 text-sm font-semibold">
            Auth token
            <input
              className={fieldClass}
              disabled={pending}
              onChange={(event) => setAuthToken(event.target.value)}
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
              aria-describedby={
                includePublicKey ? `${inputId}-api-hint` : undefined
              }
              className={fieldClass}
              disabled={pending}
              onChange={(event) => setApiKey(event.target.value)}
              type="password"
              value={apiKey}
            />
            {includePublicKey ? (
              <p
                id={`${inputId}-api-hint`}
                className="text-xs text-[var(--admin-muted)]"
              >
                For making API calls.
              </p>
            ) : null}
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
                onChange={(event) => setPublicKey(event.target.value)}
                spellCheck={false}
                type="text"
                value={publicKey}
              />
              <p
                id={`${inputId}-public-hint`}
                className="text-xs text-[var(--admin-muted)]"
              >
                Optional for AI services. Required for telephony to validate
                webhooks.
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
      {status === "success" ? (
        <p className="text-sm text-[var(--admin-green)]" role="status">
          Credential stored.
        </p>
      ) : null}
      <div className="flex justify-end gap-2">
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
        <Button disabled={pending} type="submit">
          {pending ? submittingLabel : submitLabel}
        </Button>
      </div>
    </form>
  );
}
