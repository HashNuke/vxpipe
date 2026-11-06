import { useEffect, useState } from "react";
import { parseInventory, type IntegrationInventory } from "./inventoryApi";

export type IntegrationFetch = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;
type InventoryState = { context: string; status: "loading" | "ready" | "error" | "expired" | "invalid-page" | "missing"; data: IntegrationInventory | null };

export function useInventory(url: string, context: string, tenantKey: string | null, fetchImpl: IntegrationFetch,
  onSessionExpired: () => void, revision: unknown, retry: number, cursor: string | null) {
  const [state, setState] = useState<InventoryState>({ context, status: "loading", data: null });
  useEffect(() => {
    const controller = new AbortController();
    setState(current => ({ context, status: "loading", data: current.context === context ? current.data : null }));
    fetchImpl(url, { credentials: "same-origin", headers: { accept: "application/json" }, signal: controller.signal })
      .then(async response => {
        if (controller.signal.aborted) return;
        if (response.status === 401) { onSessionExpired(); return; }
        if (!response.ok) {
          const body = response.status === 400 ? await response.json().catch(() => null) : null;
          if (controller.signal.aborted) return;
          const invalidPage = body?.error?.code === "invalid_cursor" || body?.error?.code === "cursor_mismatch";
          setState(current => ({ ...current, status: invalidPage ? "invalid-page" : response.status === 410 ? "expired" : response.status === 404 ? "missing" : "error" }));
          return;
        }
        const data = parseInventory(await response.json(), tenantKey);
        if (controller.signal.aborted) return;
        setState(current => cursor && current.data?.status === "available" && data.status === "unavailable"
          ? { ...current, status: "error" } : { context, status: "ready", data });
      }).catch(() => { if (!controller.signal.aborted) setState(current => ({ ...current, status: "error" })); });
    return () => controller.abort();
  }, [url, context, tenantKey, fetchImpl, onSessionExpired, revision, retry, cursor]);
  return state.context === context ? state : { context, status: "loading" as const, data: null };
}
