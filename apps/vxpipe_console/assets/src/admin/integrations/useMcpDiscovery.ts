import { useEffect, useState } from "react";
import { parseMcpDiscovery, validMcpUrl, type McpDiscovery, type McpSavedReference } from "./mcpDiscoveryApi";
import type { IntegrationFetch } from "./useInventory";
import type { McpListingReference } from "./listedMcp";

type Options = { tenantKey: string; csrfToken: string; endpoint: string; revision: string;
  issuer?: string; listing?: McpListingReference; connection?: McpSavedReference; active: boolean; fetchImpl: IntegrationFetch; onSessionExpired: () => void };
type State = { context: string; status: "idle" | "waiting" | "checking" | "ready" | "failed"; data: McpDiscovery | null };

/** One installation-backend request; the browser never probes arbitrary MCP URLs. */
export function useMcpDiscovery({ tenantKey, csrfToken, endpoint, revision, issuer, listing, connection, active, fetchImpl, onSessionExpired }: Options) {
  const [attempt, setAttempt] = useState(0);
  const connectionId = connection?.connection_id, generation = connection?.generation;
  const context = JSON.stringify([tenantKey, endpoint, revision, issuer, listing, connectionId, generation, active, attempt]);
  const enabled = active && validMcpUrl(endpoint);
  const [state, setState] = useState<State>({ context, status: enabled ? "waiting" : "idle", data: null });
  useEffect(() => {
    const controller = new AbortController();
    setState({ context, status: enabled ? "waiting" : "idle", data: null });
    if (!enabled) return () => controller.abort();
    const timer = window.setTimeout(() => {
      setState({ context, status: "checking", data: null });
      const saved = connectionId && generation ? { connection_id: connectionId, generation } : undefined;
      fetchImpl(`/api/tenants/${encodeURIComponent(tenantKey)}/mcp-discovery`, {
        method: "POST", credentials: "same-origin", signal: controller.signal,
        headers: { accept: "application/json", "content-type": "application/json", "x-csrf-token": csrfToken },
        body: JSON.stringify({ ...(saved ?? (listing ? { listing } : { endpoint })), revision, ...(issuer ? { issuer } : {}) }),
      }).then(async response => {
        if (controller.signal.aborted) return;
        if (response.status === 401) { onSessionExpired(); throw new Error("Session expired"); }
        if (!response.ok) throw new Error("Discovery unavailable");
        const data = parseMcpDiscovery(await response.json(), endpoint, revision, listing, saved);
        if (!controller.signal.aborted) setState({ context, status: "ready", data });
      }).catch(() => { if (!controller.signal.aborted) setState({ context, status: "failed", data: null }); });
    }, 350);
    return () => { window.clearTimeout(timer); controller.abort(); };
  }, [context, enabled, tenantKey, csrfToken, endpoint, revision, issuer, listing, connectionId, generation, fetchImpl, onSessionExpired]);
  const current = state.context === context ? state : { context, status: enabled ? "waiting" as const : "idle" as const, data: null };
  return { ...current, retry: () => setAttempt(value => value + 1) };
}
