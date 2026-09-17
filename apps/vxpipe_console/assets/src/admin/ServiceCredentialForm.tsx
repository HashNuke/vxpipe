import { useEffect, useState } from "react";

import { Button } from "./Button";
import type {
  CredentialDraft,
  CredentialSetupStatus,
  ServiceProvider,
} from "./serviceTypes";
import { validateCredentialDraft } from "./validateCredentialDraft";

const providers: Array<{ value: ServiceProvider; label: string }> = [
  { value: "google", label: "Google" },
  { value: "zenmux", label: "Zenmux" },
  { value: "deepgram", label: "Deepgram" },
  { value: "telnyx", label: "Telnyx" },
  { value: "twilio", label: "Twilio" },
];

export function ServiceCredentialForm({
  status,
  message,
  onCancel,
  onSubmit,
}: {
  status: CredentialSetupStatus;
  message?: string;
  onCancel: () => void;
  onSubmit: (draft: CredentialDraft) => void;
}) {
  const [provider, setProvider] = useState<ServiceProvider>("google");
  const [name, setName] = useState("");
  const [apiKey, setApiKey] = useState("");
  const [accountSid, setAccountSid] = useState("");
  const [authToken, setAuthToken] = useState("");
  const [validationMessage, setValidationMessage] = useState<string | null>(null);

  function clearSecrets() {
    setApiKey("");
    setAccountSid("");
    setAuthToken("");
  }

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
          name: name.trim(),
          values:
            provider === "twilio"
              ? { accountSid, authToken }
              : { apiKey },
        };
        const nextValidationMessage = validateCredentialDraft(draft);
        setValidationMessage(nextValidationMessage);
        if (!nextValidationMessage) onSubmit(draft);
      }}
    >
      <label className="grid gap-1.5 text-sm font-semibold">
        Provider
        <select
          className={fieldClass}
          disabled={pending}
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
      <label className="grid gap-1.5 text-sm font-semibold">
        Credential name
        <input
          className={fieldClass}
          disabled={pending}
          onChange={(event) => setName(event.target.value)}
          value={name}
        />
      </label>
      {provider === "twilio" ? (
        <>
          <label className="grid gap-1.5 text-sm font-semibold">
            Account SID
            <input className={fieldClass} disabled={pending} onChange={(event) => setAccountSid(event.target.value)} type="password" value={accountSid} />
          </label>
          <label className="grid gap-1.5 text-sm font-semibold">
            Auth token
            <input className={fieldClass} disabled={pending} onChange={(event) => setAuthToken(event.target.value)} type="password" value={authToken} />
          </label>
        </>
      ) : (
        <label className="grid gap-1.5 text-sm font-semibold">
          API key
          <input className={fieldClass} disabled={pending} onChange={(event) => setApiKey(event.target.value)} type="password" value={apiKey} />
        </label>
      )}
      {validationMessage ? <p className="text-sm text-[var(--admin-red)]" role="alert">{validationMessage}</p> : null}
      {message ? <p className="text-sm text-[var(--admin-red)]" role="alert">{message}</p> : null}
      {status === "success" ? <p className="text-sm text-[var(--admin-green)]" role="status">Credential stored.</p> : null}
      <div className="flex justify-end gap-2">
        <Button disabled={pending} onClick={() => { clearSecrets(); onCancel(); }} type="button" variant="ghost">Cancel</Button>
        <Button disabled={pending} type="submit">{pending ? "Saving…" : "Save credential"}</Button>
      </div>
    </form>
  );
}
