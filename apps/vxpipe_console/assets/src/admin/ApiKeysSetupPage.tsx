import { ArrowLeft, Check, Copy, Plus } from "lucide-react";
import { useState } from "react";
import { formatAdminRelativeTime } from "./formatAdminRelativeTime";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "./components/ui/tooltip";
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
  initialCreating = false,
  readOnly = false,
}: {
  tenantName: string;
  keys: TenantApiKey[];
  creation: ApiKeyCreation;
  initialKind?: TenantApiKeyKind;
  onCreate: (name: string, kind: TenantApiKeyKind) => void;
  initialCreating?: boolean;
  readOnly?: boolean;
}) {
  const [name, setName] = useState("Application");
  const [kind, setKind] = useState(initialKind);
  const [adding, setAdding] = useState(initialCreating);
  const [dismissed, setDismissed] = useState<string>();
  const created = creation.status === "created" && dismissed !== creation.key.id;
  const showForm = !readOnly && adding && !created;
  const busy = creation.status === "submitting";
  return (
    <>
      <header className="setup-section-heading">
        <div className="setup-key-heading">
          {showForm ? (
            <Button aria-label="Back to API keys" title="Back to API keys" variant="ghost" disabled={busy} onClick={() => setAdding(false)}>
              <ArrowLeft aria-hidden="true" size={16} />
              API Keys
            </Button>
          ) : null}
          <h1>{showForm ? "Create API Keys" : "API Keys"}</h1>
        </div>
        {!showForm && !readOnly ? <Button onClick={() => {
          if (creation.status === "created") setDismissed(creation.key.id);
          setAdding(true);
        }}><Plus aria-hidden="true" size={16} />Create API key</Button> : null}
      </header>
      {created && creation.status === "created" ? (
        <ApiKeyReveal key={creation.key.id} creation={creation} onDone={() => {
          setDismissed(creation.key.id);
          setAdding(false);
        }} />
      ) : null}
      {!showForm ? (
        keys.length ? <div className="setup-api-key-table-wrap">
          <table aria-label="API keys" className="setup-api-key-table">
            <thead><tr><th scope="col">Name</th><th scope="col">API key</th><th scope="col">Type</th><th scope="col">Created</th></tr></thead>
            <tbody>{keys.map(key => <tr key={key.id}>
              <td>{key.name}</td><td><code>••••••••{key.lastFour}</code></td>
              <td>{tenantApiKeyKind(key.kind).label}</td>
              <td><ApiKeyCreatedTime value={key.createdAt} /></td>
            </tr>)}</tbody>
          </table>
        </div> : <p className="setup-key-guidance">No API keys have been created for this tenant.</p>
      ) : null}
      <div className="setup-key-content">
        {showForm ? (
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
            <p className="setup-key-guidance">Use tenant API keys from your backend. Give callers short-lived join tokens to connect to a call.</p>
            <div className="setup-key-actions">
            <Button type="button" disabled={busy} onClick={() => setAdding(false)}>Cancel</Button>
            <Button
              className="setup-primary"
              disabled={busy || !name.trim()}
              type="submit"
            >
              {busy ? "Creating key…" : "Create API key"}
            </Button>
            </div>
          </form>
        ) : null}
      </div>

    </>
  );
}

function ApiKeyReveal({
  creation,
  onDone,
}: {
  creation: Extract<ApiKeyCreation, { status: "created" }>;
  onDone: () => void;
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
        Copy this key now. Once you leave this page, its value cannot be shown
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
      <div className="setup-key-actions">
      <Button onClick={() => void copy()}>
        <Copy aria-hidden="true" size={15} />
        {copyState === "copied" ? "Copied" : "Copy API key"}
      </Button>
      <Button onClick={onDone}>Done</Button>
      </div>
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

function ApiKeyCreatedTime({ value }: { value: string }) {
  const relative = formatAdminRelativeTime(value);
  return (
    <TooltipProvider>
      <Tooltip>
        <TooltipTrigger asChild>
          <time dateTime={value} tabIndex={0} className="setup-key-created-time">
            {relative === "just now" ? "few seconds ago" : relative}
          </time>
        </TooltipTrigger>
        <TooltipContent className="setup-service-tooltip" side="top" sideOffset={8}>
          {new Date(value).toUTCString().replace("GMT", "UTC")}
        </TooltipContent>
      </Tooltip>
    </TooltipProvider>
  );
}
