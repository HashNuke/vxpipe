import { useEffect, useRef, useState } from "react";
import { useLocation, useNavigate } from "react-router";
import type { OAuthHandoff } from "./CustomMcpDialog";
import type { IntegrationInventory, McpConnection } from "./inventoryApi";
import { saveOAuthDraft, takeOAuthDraft, type OAuthDraft } from "./oauthDraft";

const redirect = (url: string) => window.location.assign(url);
export type RestoredMcpDialog = { tenantKey: string; actorId?: string; connection?: McpConnection; initialDraft?: OAuthDraft };

/** Callback markers are feedback only. Current inventory remains connection authority. */
export function useOAuthReturn({ actorId, tenantKey, ready, inventory, canManageMcps, onRestore, onAuthorizationRedirect = redirect }: {
  actorId?: string; tenantKey: string | null; ready: boolean; inventory: IntegrationInventory | null; canManageMcps: boolean;
  onRestore: (dialog: RestoredMcpDialog) => void; onAuthorizationRedirect?: (url: string) => void;
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
  const [notice, setNotice] = useState<{ scope: string; text: string } | null>(null);
  const handled = useRef("");
  const callbackContext = useRef<{ identity: string; returnTo: string } | null>(null);
  useEffect(() => {
    const query = new URLSearchParams(location.search);
    if (!query.has("mcp") || !tenantKey) return;
    const status = query.get("mcp");
    const attemptId = query.get("mcp_attempt");
    const identity = `${tenantKey}:${status}:${attemptId}`;
    if (callbackContext.current?.identity !== identity) callbackContext.current = { identity, returnTo };
    if (!actorId || !ready || !inventory) return;
    const marker = `${scope}:${location.key}`;
    if (handled.current === marker) return;
    handled.current = marker;
    const valid = query.getAll("mcp").length === 1 && query.getAll("mcp_attempt").length === 1 &&
      ["connected", "denied", "failed"].includes(status ?? "") && /^[a-zA-Z0-9_-]{1,128}$/.test(attemptId ?? "");
    const draft = valid ? takeOAuthDraft({ actorId, tenantKey, attemptId: attemptId! }) : null;
    let text = "No matching sign-in attempt was found. Check your connected integrations or start again.";
    if (draft && draft.returnTo === callbackContext.current.returnTo) {
      const connection = inventory.mcpConnections.find(item => item.id === draft.connectionId);
      if (status === "connected") {
        text = connection?.status === "connected" ? `${connection.serverName} connected.` : "Could not confirm the connection. Check your connected integrations or retry.";
      } else if (!canManageMcps) {
        text = "Sign-in did not complete. You no longer have permission to change MCP connections.";
      } else if (draft.draft.generation !== undefined && (!connection || !connection.canEdit || connection.generation !== draft.draft.generation)) {
        text = "This connection changed while you were signing in. Open its current settings to continue.";
      } else {
        text = `${status === "denied" ? "Sign-in was cancelled." : "Sign-in did not complete."} Enter any credentials again to retry.`;
        onRestore({ actorId, tenantKey, initialDraft: draft.draft, ...(draft.draft.generation !== undefined ? { connection } : {}) });
      }
    }
    setNotice({ scope, text });
    navigate(returnTo, { replace: true });
  }, [actorId, tenantKey, ready, inventory, canManageMcps, scope, location.search, location.key, returnTo, navigate, onRestore]);

  function authorize(handoff: OAuthHandoff, draft: OAuthDraft) {
    if (actorId && tenantKey) saveOAuthDraft({ actorId, tenantKey, attemptId: handoff.attemptId, connectionId: handoff.connectionId, returnTo, draft });
    onAuthorizationRedirect(handoff.authorizationUrl);
  }
  return { returnTo, authorize, notice: notice?.scope === scope ? notice.text : null };
}
