import { useEffect, useRef, useState, type ReactNode } from "react";
import { Button } from "./Button";
import { LoaderCircle } from "lucide-react";
import { TelnyxConnectionDialog, type TelnyxConnectionChanges } from "./TelnyxConnectionDialog";
import { parseTelnyxConnection, telnyxSaveError, type TelnyxConnection } from "./telnyxConnectionApi";
import type { CredentialDraft, CredentialTestResult } from "./serviceTypes";
import type { SetupServiceScope } from "./setupCatalog";

export function TelnyxConnectionModal({ scope, csrfToken, fetchImpl, onClose, onSaved, onSessionExpired, onTest, canEditCredentials = true, canEditApplication = true }: {
  scope: SetupServiceScope; csrfToken: string;
  fetchImpl: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;
  onTest?: (draft: CredentialDraft) => Promise<CredentialTestResult>;
  canEditCredentials?: boolean; canEditApplication?: boolean;
  onClose: () => void; onSaved: () => void; onSessionExpired: () => void;
}) {
  const [connection, setConnection] = useState<TelnyxConnection | null>(null);
  const [selection, setSelection] = useState<string | null>(null);
  const [message, setMessage] = useState<string>();
  const [retry, setRetry] = useState(0);
  const [pending, setPending] = useState(false);
  const saving = useRef<AbortController | null>(null);
  const tenantKey = scope.kind === "tenant" ? scope.tenantKey : null;
  const url = `${tenantKey ? `/api/tenants/${encodeURIComponent(tenantKey)}` : "/api/platform"}/telnyx-connection`;

  useEffect(() => {
    const controller = new AbortController();
    setMessage(undefined);
    fetchImpl(url, { credentials: "same-origin", headers: { accept: "application/json" }, signal: controller.signal })
      .then(async response => {
        if (controller.signal.aborted) return;
        if (response.status === 401) onSessionExpired();
        if (!response.ok) throw new Error("unavailable");
        const next = parseTelnyxConnection(await response.json(), tenantKey
          ? { kind: "tenant", tenantKey, tenantName: "" } : { kind: "platform" });
        if (!controller.signal.aborted) {
          setConnection(next);
          setSelection(next.applications.length === 1 ? next.applications[0].id : null);
        }
      }).catch(() => { if (!controller.signal.aborted) setMessage("Telnyx settings could not be loaded. Try again."); });
    return () => { controller.abort(); saving.current?.abort(); };
  }, [url, tenantKey, fetchImpl, onSessionExpired, retry]);

  async function save(changes: TelnyxConnectionChanges) {
    if (saving.current) return;
    const controller = new AbortController();
    saving.current = controller;
    setPending(true);
    setMessage(undefined);
    try {
      const response = await fetchImpl(url, { method: "PATCH", credentials: "same-origin", signal: controller.signal,
        headers: { accept: "application/json", "content-type": "application/json", "x-csrf-token": csrfToken },
        body: JSON.stringify({ ...changes, ...(changes.application_id !== undefined && selection ? { service_id: selection } : {}) }) });
      if (controller.signal.aborted) return;
      if (response.status === 401) { onSessionExpired(); throw new Error("Your session expired. Sign in again."); }
      if (!response.ok) throw new Error(telnyxSaveError(response.status, await response.json().catch(() => null)));
      onSaved();
    } catch (error) {
      if (!controller.signal.aborted) setMessage(error instanceof Error ? error.message : "Telnyx settings could not be saved. Try again.");
    } finally {
      if (saving.current === controller) saving.current = null;
      if (!controller.signal.aborted) setPending(false);
    }
  }

  let content: ReactNode;
  if (!connection) content = <div className="mcp-dialog-form telnyx-connection-form">
    <div className="mcp-dialog-scroll telnyx-connection-loading">
      {message ? <div><p role="alert">{message}</p><Button onClick={() => setRetry(value => value + 1)}>Retry</Button></div>
        : <p role="status"><LoaderCircle size={16} aria-hidden="true" className="animate-spin motion-reduce:animate-none" />Loading Telnyx settings…</p>}
    </div>
    <footer className="mcp-dialog-footer telnyx-connection-footer"><Button data-telnyx-close variant="ghost" onClick={onClose}>Cancel</Button></footer>
  </div>;
  else if (connection.applications.length > 1 && !selection) content = <div className="mcp-dialog-form telnyx-connection-form">
    <div className="mcp-dialog-scroll grid content-start gap-2">
      <h3>Choose voice application</h3>
      {connection.applications.map(application => <Button key={application.id} onClick={() => setSelection(application.id)}>{application.name}</Button>)}
    </div>
    <footer className="mcp-dialog-footer telnyx-connection-footer"><Button data-telnyx-close variant="ghost" onClick={onClose}>Cancel</Button></footer>
  </div>;
  const application = connection?.applications.find(item => item.id === selection);
  return <TelnyxConnectionDialog formKey={selection ?? "new"} content={content} scope={scope}
    canEditCredentials={canEditCredentials} canEditApplication={canEditApplication}
    state={{ provider: "telnyx", status: pending ? "submitting" : message ? "error" : "idle", message }}
    connections={connection?.credential ? [connection.credential] : []}
    platformConnections={connection?.platformAvailable ? [{ provider: "telnyx", source: "platform", status: "connected" }] : []}
    applicationId={tenantKey ? application?.provider_connection_id ?? "" : connection?.platformApplicationId ?? ""}
    applicationExists={!tenantKey || Boolean(application)} platformApplicationId={connection?.platformApplicationId ?? ""}
    webhookUrls={connection?.webhookUrls} onTest={onTest} onClose={() => { if (!saving.current) onClose(); }} onSave={save} />;
}
