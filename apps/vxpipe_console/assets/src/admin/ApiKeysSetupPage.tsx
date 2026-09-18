import { ArrowLeft, ArrowRight, Check, Copy, KeyRound } from "lucide-react";
import { useState } from "react";
import { Button } from "./Button";
import {
  tenantApiKeyKind,
  tenantApiKeyKinds,
  type ApiKeyCreation,
  type TenantApiKey,
  type TenantApiKeyKind,
} from "./tenantApiKeys";

export function ApiKeysSetupPage({
  tenantName,
  keys,
  creation,
  initialKind = "calls",
  onCreate,
  onServices,
  onCallSpecs,
}: {
  tenantName: string;
  keys: TenantApiKey[];
  creation: ApiKeyCreation;
  initialKind?: TenantApiKeyKind;
  onCreate: (name: string, kind: TenantApiKeyKind) => void;
  onServices: () => void;
  onCallSpecs: () => void;
}) {
  const [name, setName] = useState("Application");
  const [kind, setKind] = useState(initialKind);
  const [adding, setAdding] = useState(false);
  const busy = creation.status === "submitting";
  return (
    <>
      <Button
        className="setup-back"
        disabled={busy}
        onClick={onServices}
        variant="ghost"
      >
        <ArrowLeft aria-hidden="true" size={15} />
        Back to services
      </Button>
      <header className="setup-page-heading">
        <h1>Create API Keys</h1>
        <p>
          Give your application access to {tenantName}. Choose the permissions
          it needs.
        </p>
      </header>
      <div className="setup-key-content">
        <p className="setup-key-guidance">
          Use tenant API keys from your backend. Give callers short-lived join
          tokens to connect to a call.
        </p>
        {creation.status === "created" ? (
          <ApiKeyReveal creation={creation} />
        ) : null}
        {keys.length > 0 && creation.status !== "created" ? (
          <section aria-label="Tenant API keys" className="setup-saved-keys">
            <h2>Keys for {tenantName}</h2>
            {keys.map((key) => (
              <div className="setup-saved-key" key={key.id}>
                <KeyRound aria-hidden="true" size={18} />
                <div>
                  <strong>{key.name}</strong>
                  <p>{tenantApiKeyKind(key.kind).label}</p>
                </div>
                <span>Created</span>
              </div>
            ))}
            <p>
              Key values are shown only when created. Create another key if you
              need a new value.
            </p>
            {!adding ? (
              <Button onClick={() => setAdding(true)}>
                Create another API key
              </Button>
            ) : null}
          </section>
        ) : null}
        {creation.status !== "created" && (keys.length === 0 || adding) ? (
          <form
            className="setup-key-form"
            onSubmit={(event) => {
              event.preventDefault();
              if (name.trim() && !busy) onCreate(name.trim(), kind);
            }}
          >
            <label className="setup-key-name">
              Key name
              <input
                disabled={busy}
                maxLength={256}
                onChange={(event) => setName(event.target.value)}
                required
                value={name}
              />
            </label>
            <fieldset disabled={busy}>
              <legend>Access for this tenant</legend>
              <div className="setup-key-options">
                {tenantApiKeyKinds.map((option) => (
                  <label
                    className="setup-key-option"
                    data-selected={kind === option.id}
                    key={option.id}
                  >
                    <input
                      aria-label={option.label}
                      checked={kind === option.id}
                      name="key-access"
                      onChange={() => setKind(option.id)}
                      type="radio"
                      value={option.id}
                    />
                    <span>
                      <strong>{option.label}</strong>
                      <span className="setup-key-description">
                        {option.description}
                      </span>
                    </span>
                  </label>
                ))}
              </div>
              <p className="setup-key-boundary">
                Both options are limited to {tenantName}. Platform
                administration and other tenants are separate.
              </p>
            </fieldset>
            {creation.status === "error" ? (
              <p className="setup-error" role="alert">
                The API key could not be created. Your name and access choice
                are kept here; try again.
              </p>
            ) : null}
            <Button
              className="setup-primary"
              disabled={busy || !name.trim()}
              type="submit"
            >
              {busy ? "Creating key…" : "Create API key"}
            </Button>
          </form>
        ) : null}
      </div>
      <footer className="setup-footer">
        <p>
          {keys.length
            ? "You can now set up call specs for this tenant."
            : "You can create a key now or return to this step later."}
        </p>
        <Button
          className={keys.length ? "setup-primary" : undefined}
          disabled={busy}
          onClick={onCallSpecs}
        >
          Continue to Setup Call Specs
          <ArrowRight aria-hidden="true" size={16} />
        </Button>
      </footer>
    </>
  );
}

function ApiKeyReveal({
  creation,
}: {
  creation: Extract<ApiKeyCreation, { status: "created" }>;
}) {
  const [copyState, setCopyState] = useState<"idle" | "copied" | "error">(
    "idle",
  );
  async function copy() {
    try {
      await navigator.clipboard.writeText(creation.secret);
      setCopyState("copied");
    } catch {
      setCopyState("error");
    }
  }
  const option = tenantApiKeyKind(creation.key.kind);
  return (
    <section aria-label="API key created" className="setup-key-created">
      <h2>
        <Check aria-hidden="true" size={18} />
        API key created
      </h2>
      <div className="setup-key-created-meta">
        <strong>{creation.key.name}</strong>
        <span>{option.label}</span>
      </div>
      <p>
        Copy this key now. Once you leave this step, its value cannot be shown
        again.
      </p>
      <label className="setup-key-name">
        API key
        <input
          onFocus={(event) => event.target.select()}
          readOnly
          value={creation.secret}
        />
      </label>
      <Button onClick={() => void copy()}>
        <Copy aria-hidden="true" size={15} />
        {copyState === "copied" ? "Copied" : "Copy API key"}
      </Button>
      <p className="setup-key-copy-status" role="status">
        {copyState === "error"
          ? "Copy failed. Select the key above and copy it manually."
          : copyState === "copied"
            ? "API key copied."
            : ""}
      </p>
    </section>
  );
}
