import { Building2, LoaderCircle } from "lucide-react";
import { useEffect, useId, useRef, useState, type ReactNode } from "react";
import { Button } from "./Button";
import { ApiKeyCredentialFields, credentialInputClass } from "./credentials/ApiKeyCredentialFields";
import { SetupDialog } from "./SetupDialog";
import { TelnyxWebhookField } from "./TelnyxWebhookField";
import { telnyxWebhookUrl } from "./setupPublicOrigin";
import { validateCredentialDraft } from "./validateCredentialDraft";
import type { CredentialDraft, CredentialTestResult } from "./serviceTypes";
import type { ServiceModalState } from "./ServiceSetupModal";
import type { SetupConnection, SetupServiceScope } from "./setupCatalog";

export type TelnyxConnectionChanges = {
  application_id?: string | null;
  credentials?: { api_key?: string; public_key?: string } | null;
};
export type TelnyxConnectionDialogProps = {
  content?: ReactNode;
  formKey?: string;
  state: ServiceModalState;
  scope: SetupServiceScope;
  connections?: SetupConnection[];
  platformConnections?: SetupConnection[];
  applicationId?: string;
  platformApplicationId?: string;
  applicationExists?: boolean;
  canEditCredentials?: boolean;
  canEditApplication?: boolean;
  publicOrigin?: string;
  webhookUrls?: { platform: string; tenant: string | null };
  onClose: () => void;
  onSave: (changes: TelnyxConnectionChanges) => void;
  onTest?: (draft: CredentialDraft) => Promise<CredentialTestResult>;
};
import telnyxIcon from "./assets/icons/telnyx.png";
import "./telnyx-connection.css";

/** Keep the frame mounted while its settings, selection, or form changes. */
export function TelnyxConnectionDialog({ content, formKey, ...props }: TelnyxConnectionDialogProps) {
  const [testing, setTesting] = useState(false);
  const busy = testing || props.state.status === "submitting" || props.state.status === "testing";
  const onTest = props.onTest;
  const testCredentials = onTest ? async (draft: CredentialDraft): Promise<CredentialTestResult> => {
    setTesting(true);
    try {
      return await onTest(draft);
    } finally {
      setTesting(false);
    }
  } : undefined;
  return <SetupDialog title="Telnyx" anchorTop busy={busy} onClose={props.onClose}
    initialFocusSelector={content || props.connections?.length ? "[data-telnyx-close]" : undefined}
    headerContent={<div className="telnyx-connection-title">
      <img src={telnyxIcon} alt="" width={28} height={28} />
      <div><span>Telnyx</span><p>{props.scope.kind === "tenant" ? props.scope.tenantName : "Platform connection"}</p></div>
    </div>}>
    {content ?? <TelnyxConnectionForm key={formKey} {...props} onTest={testCredentials} />}
  </SetupDialog>;
}

function TelnyxConnectionForm({
  state, scope, connections = [], platformConnections = [], applicationId = "",
  platformApplicationId = "", applicationExists = true, publicOrigin, webhookUrls,
  canEditCredentials = true, canEditApplication = true,
  onClose, onSave, onTest,
}: TelnyxConnectionDialogProps) {
  const id = useId();
  const tenant = scope.kind === "tenant";
  const selected = connections.find(item => item.provider === "telnyx");
  const platform = platformConnections.find(item => item.provider === "telnyx");
  const initiallyInherited = tenant && selected?.source === "platform";
  const canReplaceCredentials = canEditCredentials && (!tenant || canEditApplication);
  const [inheritedCredentials, setInheritedCredentials] = useState(initiallyInherited);
  const [editingCredentials, setEditingCredentials] = useState(!selected && !initiallyInherited && canReplaceCredentials);
  const [inheritedApplication, setInheritedApplication] = useState(tenant && !applicationId && initiallyInherited);
  const [application, setApplication] = useState(applicationId || platformApplicationId);
  const [apiKey, setApiKey] = useState("");
  const [publicKey, setPublicKey] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [applicationError, setApplicationError] = useState(false);
  const [testResult, setTestResult] = useState<CredentialTestResult | { status: "testing" } | null>(null);
  const fieldsRef = useRef<HTMLDivElement>(null);
  const cancelRef = useRef<HTMLButtonElement>(null);
  const applicationRef = useRef<HTMLInputElement>(null);
  const errorRef = useRef<HTMLParagraphElement>(null);
  const pending = state.status === "submitting" || state.status === "testing" || testResult?.status === "testing";
  const credentialsChanged = canReplaceCredentials && editingCredentials && !inheritedCredentials;
  const effectiveScope = inheritedCredentials && inheritedApplication ? { kind: "platform" as const } : scope;
  const webhookUrl = webhookUrls
    ? effectiveScope.kind === "platform" ? webhookUrls.platform : webhookUrls.tenant
    : publicOrigin ? telnyxWebhookUrl(publicOrigin, effectiveScope) : null;
  const effectiveConnection = inheritedCredentials ? initiallyInherited ? selected : platform : selected;

  useEffect(() => {
    if (credentialsChanged) fieldsRef.current?.querySelector<HTMLInputElement>("input")?.focus();
    else cancelRef.current?.focus();
  }, [credentialsChanged]);
  useEffect(() => {
    if (error && !applicationError) errorRef.current?.focus();
  }, [error, applicationError]);

  function editCredentials() {
    setInheritedCredentials(false);
    setEditingCredentials(true);
    setTestResult(null);
    setError(null);
    if (tenant) {
      setInheritedApplication(false);
      setApplication("");
      setApplicationError(false);
    }
  }
  function usePlatformCredentials() {
    setInheritedCredentials(true);
    setEditingCredentials(false);
    setApiKey("");
    setPublicKey("");
    setError(null);
    setTestResult(null);
  }
  function credentialDraft(): CredentialDraft | null {
    const draft: CredentialDraft = { provider: "telnyx", values: { apiKey, ...(publicKey.trim() ? { publicKey: publicKey.trim() } : {}) } };
    const invalid = validateCredentialDraft(draft);
    setError(invalid);
    return invalid ? null : draft;
  }
  function save() {
    const resolvedApplication = inheritedApplication ? platformApplicationId : application.trim();
    if (!/^[\x21-\x7e]{1,128}$/.test(resolvedApplication) ||
        (tenant && !inheritedApplication && resolvedApplication === platformApplicationId)) {
      setError("Enter a separate Voice API application ID without spaces.");
      setApplicationError(true);
      applicationRef.current?.focus();
      return;
    }
    const changes: TelnyxConnectionChanges = {};
    const nextApplication = inheritedApplication ? null : resolvedApplication;
    const initialApplication = tenant ? applicationId || null : platformApplicationId || null;
    if (canEditApplication && (!applicationExists || nextApplication !== initialApplication || (tenant && credentialsChanged))) {
      changes.application_id = nextApplication;
    }
    if (credentialsChanged) {
      const savedOwn = selected && !initiallyInherited;
      const invalid = validateCredentialDraft({ provider: "telnyx", values: {
        apiKey: apiKey || (savedOwn ? "saved" : ""),
        ...(publicKey.trim() ? { publicKey: publicKey.trim() } : {}),
      } });
      if (invalid || (!publicKey.trim() && !savedOwn)) {
        setApplicationError(false);
        setError(invalid ?? "Enter the public key.");
        return;
      }
      changes.credentials = {
        ...(apiKey ? { api_key: apiKey } : {}),
        ...(publicKey.trim() ? { public_key: publicKey.trim() } : {}),
      };
    } else if (canEditCredentials && inheritedCredentials && !initiallyInherited && selected) changes.credentials = null;
    if (Object.keys(changes).length) onSave(changes);
    else onClose();
  }
  async function testCredentials() {
    const draft = credentialDraft();
    if (!draft || !onTest) return;
    setTestResult({ status: "testing" });
    try {
      setTestResult(await onTest(draft));
    } catch {
      setTestResult({ status: "error", message: "Credentials could not be tested. Try again." });
    }
  }

  return (
    <form className="mcp-dialog-form telnyx-connection-form" noValidate onSubmit={event => { event.preventDefault(); save(); }}>
      <div className="mcp-dialog-scroll telnyx-connection-body">
        <section className="telnyx-setting" aria-labelledby={`${id}-credentials`}>
          <div className="telnyx-setting-heading">
            <h3 id={`${id}-credentials`}>Credentials</h3>
            <div className="telnyx-setting-actions">
              {canReplaceCredentials && (inheritedCredentials ? <Button type="button" aria-label="Override credentials" disabled={pending} onClick={editCredentials}>Override</Button>
                : !editingCredentials ? <Button type="button" variant="ghost" aria-label="Edit credentials" disabled={pending} onClick={editCredentials}>Edit</Button> : null)}
              {canEditCredentials && tenant && !inheritedCredentials && platform ? <Button type="button" aria-label="Use platform default for credentials" disabled={pending} onClick={usePlatformCredentials}>Use platform default</Button> : null}
            </div>
          </div>
          {credentialsChanged ? <div className="telnyx-credential-fields" ref={fieldsRef}>
            <ApiKeyCredentialFields value={apiKey} disabled={pending} onChange={value => { setApiKey(value); setError(null); setTestResult(null); }} placeholder={selected && !initiallyInherited ? "Leave blank to keep saved API key" : "Enter API key"} />
            <div className="grid gap-1.5 text-sm">
              <label className="font-semibold" htmlFor={`${id}-public`}>Public key</label>
              <input className={credentialInputClass} id={`${id}-public`} aria-describedby={`${id}-public-hint`} value={publicKey} disabled={pending} spellCheck={false}
                placeholder={selected && !initiallyInherited ? "Leave blank to keep saved public key" : "Enter public key"}
                onChange={event => { setPublicKey(event.target.value); setError(null); setTestResult(null); }} />
              <p id={`${id}-public-hint`} className="text-xs text-[var(--admin-muted)]">Note: Public key is only required if you use Telephony services</p>
            </div>
          </div> : <dl className="telnyx-credential-summary">
            <div><dt>API key</dt><dd><span aria-label="Saved API key" className="telnyx-masked-key">••••••••••••</span><span>Saved</span></dd></div>
            <div><dt>Public key</dt><dd>{inheritedCredentials && !initiallyInherited ? "Platform default" : effectiveConnection?.telephonyPublicKeyConfigured || effectiveConnection?.savedFields?.includes("publicKey") ? <><span aria-label="Saved public key" className="telnyx-masked-key">••••••••••••</span><span>Saved</span></> : "Not configured"}</dd></div>
          </dl>}
        </section>

        <section className="telnyx-setting" aria-labelledby={`${id}-voice`}>
          <div className="telnyx-setting-heading">
            <div><h3 id={`${id}-voice`}>Voice application</h3><p className="telnyx-setting-source">
              {inheritedApplication || !tenant ? <Building2 size={13} aria-hidden="true" /> : null}
              {inheritedApplication || !tenant ? "Platform default" : "Tenant override"}
            </p></div>
            {canEditApplication && (inheritedApplication ? <Button type="button" aria-label="Override voice application" disabled={pending} onClick={() => { setInheritedApplication(false); applicationRef.current?.focus(); }}>Override</Button>
              : tenant && inheritedCredentials && platformApplicationId ? <Button type="button" aria-label="Use platform default for voice application" disabled={pending}
                onClick={() => { setInheritedApplication(true); setApplicationError(false); setError(null); }}>Use platform default</Button> : null)}
          </div>
          <label className="telnyx-field-label" htmlFor={`${id}-application`}>Voice API application ID</label>
          <input id={`${id}-application`} ref={applicationRef} className={`${credentialInputClass} telnyx-application-value`}
            value={inheritedApplication ? platformApplicationId : application} readOnly={inheritedApplication || !canEditApplication} disabled={pending}
            maxLength={128} spellCheck={false} placeholder="Enter application ID" aria-invalid={applicationError}
            aria-describedby={`${id}-application-hint`}
            onChange={event => { setApplication(event.target.value); setApplicationError(false); setError(null); }} />
          <p id={`${id}-application-hint`} className="telnyx-field-hint">
            {inheritedApplication || !tenant ? "Shared across tenants. Each phone number routes to its assigned call spec." : "Use a separate voice application for this tenant."}
          </p>
          {webhookUrl ? <div className="telnyx-webhook-section"><TelnyxWebhookField key={webhookUrl} url={webhookUrl} /></div> : null}
        </section>
        {error || state.message ? <p className="telnyx-connection-error" role="alert" tabIndex={-1} ref={errorRef}>{error ?? state.message}</p> : null}
        {testResult?.status === "valid" ? <p className="telnyx-connection-success" role="status">Credentials tested successfully.</p> : null}
        {testResult?.status === "error" ? <p className="telnyx-connection-error" role="alert">{testResult.message}</p> : null}
        {pending ? <p className="telnyx-connection-progress" role="status"><LoaderCircle size={16} aria-hidden="true" className="animate-spin motion-reduce:animate-none" />{testResult?.status === "testing" || state.status === "testing" ? "Testing credentials…" : "Saving connection…"}</p> : null}
      </div>
      <footer className="mcp-dialog-footer telnyx-connection-footer">
        <Button type="button" ref={cancelRef} data-telnyx-close variant="ghost" disabled={pending} onClick={onClose}>Cancel</Button>
        {credentialsChanged && onTest ? <Button type="button" variant="ghost" disabled={pending} onClick={() => void testCredentials()}>Test credentials</Button> : null}
        <Button className="mcp-primary" type="submit" disabled={pending}>{state.status === "submitting" ? "Saving…" : "Save"}</Button>
      </footer>
    </form>
  );
}
