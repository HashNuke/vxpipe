import { useEffect, useRef, useState } from "react";
import { useLocation, useNavigate } from "react-router";
import type { OAuthHandoff } from "./CustomMcpDialog";
import type { IntegrationInventory, McpConnection } from "./inventoryApi";
import { saveOAuthDraft, takeOAuthDraft, type OAuthDraft, type StoredOAuthDraft } from "./oauthDraft";
import { recoverRetainedOAuth } from "./retainedOAuthReturn";

const redirect = (url: string) => window.location.assign(url);
export type RestoredMcpDialog = { tenantKey: string; actorId?: string; connection?: McpConnection; initialDraft?: OAuthDraft };

/** Callback markers are feedback only. Authorized inventory/metadata reads remain connection authority. */
export function useOAuthReturn({ actorId, tenantKey, ready, inventory, canManageMcps, onRestore, fetchImpl = fetch, onSessionExpired, onAuthorizationRedirect = redirect }: {
  actorId?: string; tenantKey: string | null; ready: boolean; inventory: IntegrationInventory | null; canManageMcps: boolean;
  onRestore: (dialog: RestoredMcpDialog) => void; onAuthorizationRedirect?: (url: string) => void;
  fetchImpl?: typeof fetch; onSessionExpired?: () => void;
}) {
  const location = useLocation();
  const navigate = useNavigate();
  const params = new URLSearchParams(location.search);
  const clean = new URLSearchParams();
  for (const name of ["q", "cursor"]) {
    const value = params.get(name);
    if (value && !Array.from(value).some(char => char.charCodeAt(0) < 32 || char.charCodeAt(0) === 127) && value.length <= (name === "q" ? 200 : 2048)) clean.set(name, value);
  }
  const returnTo = `${location.pathname}${clean.size ? `?${clean}` : ""}`;
  const scope = `${actorId}:${tenantKey}`;
  const [notice, setNotice] = useState<{ scope: string; text: string; retry?: boolean } | null>(null);
  const [retry, setRetry] = useState(0);
  const pending = useRef<{ identity: string; draft: StoredOAuthDraft } | null>(null);
  const handled = useRef("");
  const callbackContext = useRef<{ identity: string; returnTo: string } | null>(null);
  useEffect(() => {
    const query = new URLSearchParams(location.search);
    if (!query.has("mcp") || !tenantKey) {
      if (pending.current) { pending.current = null; setNotice(null); }
      callbackContext.current = null;
      return;
    }
    const status = query.get("mcp");
    const attemptId = query.get("mcp_attempt");
    const identity = `${tenantKey}:${status}:${attemptId}`;
    const attemptScope = `${scope}:${status}:${attemptId}`;
    if (pending.current?.identity !== attemptScope) pending.current = null;
    if (callbackContext.current?.identity !== identity) callbackContext.current = { identity, returnTo };
    if (!actorId || !ready || !inventory) return;
    const marker = `${scope}:${location.key}`;
    if (handled.current === marker) return;
    const valid = query.getAll("mcp").length === 1 && query.getAll("mcp_attempt").length === 1 &&
      ["connected", "denied", "failed"].includes(status ?? "") && /^[a-zA-Z0-9_-]{1,128}$/.test(attemptId ?? "");
    const candidate = valid ? pending.current?.draft ?? takeOAuthDraft({ actorId, tenantKey, attemptId: attemptId! }) : null;
    const draft = candidate && candidate.createdAt <= Date.now() && Date.now() - candidate.createdAt <= 300_000 ? candidate : null;
    const controller = new AbortController();
    const changed = "This connection changed while you were signing in. Open its current settings to continue.";
    const denied = "Sign-in did not complete. You no longer have permission to change MCP connections.";
    const retryText = `${status === "denied" ? "Sign-in was cancelled." : "Sign-in did not complete."} Enter any credentials again to retry.`;
    function finish(text: string, restore?: RestoredMcpDialog) {
      if (controller.signal.aborted) return;
      handled.current = marker;
      pending.current = null;
      setNotice({ scope, text });
      if (restore) onRestore(restore);
      navigate(returnTo, { replace: true });
    }
    let text = "No matching sign-in attempt was found. Check your connected integrations or start again.";
    if (draft && draft.returnTo === callbackContext.current.returnTo) {
      const connection = inventory.mcpConnections.find(item => item.id === draft.connectionId);
      if (status === "connected") {
        text = connection?.status === "connected" ? `${connection.serverName} connected.` : "Could not confirm the connection. Check your connected integrations or retry.";
      } else if (!canManageMcps) {
        text = denied;
      } else if (draft.draft.generation !== undefined && !connection) {
        pending.current = { identity: attemptScope, draft };
        setNotice({ scope, text: "Loading the disconnected connection…" });
        void recoverRetainedOAuth(draft, fetchImpl, controller.signal).then(result => {
          if (controller.signal.aborted) return;
          if (result.kind === "ready") finish(retryText, { actorId, tenantKey, connection: result.connection, initialDraft: draft.draft });
          else if (result.kind === "unavailable") setNotice({ scope, text: "Could not load the disconnected connection. Retry recovery to continue.", retry: true });
          else if (result.kind === "expired") { onSessionExpired?.(); finish("Your session expired. Sign in again to continue."); }
          else finish(result.kind === "forbidden" ? denied : changed);
        });
        return () => controller.abort();
      } else if (draft.draft.generation !== undefined && (!connection?.canEdit || connection.generation !== draft.draft.generation || connection.endpoint !== draft.draft.endpoint)) {
        text = changed;
      } else {
        finish(retryText, { actorId, tenantKey, initialDraft: draft.draft, ...(draft.draft.generation !== undefined ? { connection } : {}) });
        return () => controller.abort();
      }
    }
    finish(text);
    return () => controller.abort();
  }, [actorId, tenantKey, ready, inventory, canManageMcps, scope, location.search, location.key, returnTo, navigate, onRestore, fetchImpl, onSessionExpired, retry]);

  function authorize(handoff: OAuthHandoff, draft: OAuthDraft) {
    if (actorId && tenantKey) saveOAuthDraft({ actorId, tenantKey, attemptId: handoff.attemptId, connectionId: handoff.connectionId, returnTo, draft });
    onAuthorizationRedirect(handoff.authorizationUrl);
  }
  return { returnTo, authorize, notice: notice?.scope === scope ? notice.text : null,
    retryRecovery: notice?.scope === scope && notice.retry ? () => setRetry(value => value + 1) : undefined };
}
