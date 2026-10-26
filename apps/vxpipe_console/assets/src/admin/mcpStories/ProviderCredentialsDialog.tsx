import { CircleAlert, CircleCheck, LoaderCircle } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { Button } from "../Button";
import { SetupDialog } from "../SetupDialog";
import {
  setupProvider,
  type SetupProviderId,
} from "../setupCatalog";
import type { CredentialDraft } from "../serviceTypes";
import { validateCredentialDraft } from "../validateCredentialDraft";
import { telnyxWebhookUrl } from "../setupPublicOrigin";
import { CopyField, TextField } from "./FormControls";
import { installationUrl } from "./fixtures";

/** Fixed-provider credentials preview. Testing/saving never sends a request. */
export function ProviderCredentialsDialog({
  providerId,
  tenant,
  editing = false,
  onClose,
  onConnect,
}: {
  providerId: SetupProviderId;
  tenant: { key: string; name: string };
  editing?: boolean;
  onClose: () => void;
  onConnect: (publicKeyConfigured: boolean) => void;
}) {
  const provider = setupProvider(providerId);
  const [apiKey, setApiKey] = useState("");
  const [publicKey, setPublicKey] = useState("");
  const [accountSid, setAccountSid] = useState("");
  const [authToken, setAuthToken] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<
    "idle" | "testing" | "tested" | "saving"
  >("idle");
  const errorRef = useRef<HTMLDivElement>(null);
  const active = useRef(true);
  useEffect(() => {
    active.current = true;
    return () => {
      active.current = false;
    };
  }, []);
  useEffect(() => {
    if (error) {
      errorRef.current?.focus();
      errorRef.current?.scrollIntoView?.({ block: "nearest" });
    }
  }, [error]);
  const pending = status === "testing" || status === "saving";
  const canTest = !["cartesia", "elevenlabs", "fireworks"].includes(providerId);
  function changed(set: (value: string) => void, value: string) {
    set(value);
    setError(null);
    setStatus("idle");
  }
  async function submit(test: boolean) {
    const draft: CredentialDraft =
      providerId === "twilio"
        ? { provider: providerId, values: { accountSid, authToken } }
        : {
            provider: providerId,
            values: {
              apiKey,
              ...(providerId === "telnyx" && publicKey.trim()
                ? { publicKey: publicKey.trim() }
                : {}),
            },
          };
    const invalid = validateCredentialDraft(draft);
    if (invalid) {
      setError(invalid);
      errorRef.current?.focus();
      return;
    }
    setStatus(test ? "testing" : "saving");
    await new Promise((resolve) => setTimeout(resolve, 350));
    if (!active.current) return;
    if (test) setStatus("tested");
    else onConnect(Boolean(publicKey.trim()));
  }
  return (
    <SetupDialog
      title={`${editing ? "Manage" : "Connect"} ${provider.name}`}
      anchorTop
      busy={pending}
      onClose={onClose}
    >
      <form
        className="mcp-dialog-form provider-credentials-form"
        noValidate
        onSubmit={(event) => {
          event.preventDefault();
          void submit(false);
        }}
      >
        <div className="mcp-dialog-scroll">
          {editing && (
            <p className="provider-credentials-context">
              Enter new credentials to update this tenant’s connection.
            </p>
          )}
          {providerId === "twilio" ? (
            <>
              <TextField
                label="Account SID"
                value={accountSid}
                placeholder="AC…"
                disabled={pending}
                onChange={(event) => changed(setAccountSid, event.target.value)}
              />
              <TextField
                label="Auth token"
                secret
                value={authToken}
                disabled={pending}
                placeholder="Enter auth token"
                onChange={(event) => changed(setAuthToken, event.target.value)}
              />
            </>
          ) : (
            <TextField
              label="API key"
              secret
              value={apiKey}
              disabled={pending}
              placeholder="Enter API key"
              onChange={(event) => changed(setApiKey, event.target.value)}
            />
          )}
          {providerId === "telnyx" && (
            <>
              <TextField
                label="Public key"
                value={publicKey}
                disabled={pending}
                placeholder="Enter public key"
                hint="Used to verify incoming telephony webhooks."
                onChange={(event) => changed(setPublicKey, event.target.value)}
              />
              <section className="provider-webhook">
                <h3>Incoming calls</h3>
                <p className="mcp-hint">
                  Use this webhook URL in your Telnyx Voice API application.
                </p>
                <CopyField
                  label="Webhook URL"
                  value={telnyxWebhookUrl(installationUrl, {
                    kind: "tenant",
                    tenantKey: tenant.key,
                    tenantName: tenant.name,
                  })}
                />
              </section>
            </>
          )}
          {error && (
            <div
              className="mcp-error"
              ref={errorRef}
              tabIndex={-1}
              role="alert"
            >
              <CircleAlert size={17} aria-hidden />
              <p>{error}</p>
            </div>
          )}
          {status === "tested" && (
            <p className="mcp-notice" role="status">
              <CircleCheck size={16} aria-hidden />
              Credentials verified.
            </p>
          )}
          {pending && (
            <p className="mcp-hint provider-credentials-progress" role="status">
              <LoaderCircle className="mcp-spinner" size={16} aria-hidden />
              {status === "testing"
                ? "Testing credentials…"
                : "Saving connection…"}
            </p>
          )}

        </div>
        <footer className="mcp-dialog-footer provider-credentials-footer">
          <Button type="button" disabled={pending} onClick={onClose}>
            Cancel
          </Button>
          {canTest && (
            <Button
              type="button"
              disabled={pending}
              onClick={() => void submit(true)}
            >
              Test credentials
            </Button>
          )}
          <Button className="mcp-primary" type="submit" disabled={pending}>
            {status === "saving"
              ? "Saving…"
              : editing
                ? "Save changes"
                : "Connect"}
          </Button>
        </footer>
      </form>
    </SetupDialog>
  );
}
