import { conflictUrl, parseConflictConnection } from "./mcpConflict";
import type { McpConnection } from "./inventoryApi";
import type { StoredOAuthDraft } from "./oauthDraft";

type Recovery = { kind: "ready"; connection: McpConnection } | { kind: "changed" | "forbidden" | "expired" | "unavailable" };

export async function recoverRetainedOAuth(draft: StoredOAuthDraft, fetchImpl: typeof fetch, signal: AbortSignal): Promise<Recovery> {
  const conflict = { kind: "reconnect" as const, id: draft.connectionId, generation: draft.draft.generation! };
  let response: Response;
  try { response = await fetchImpl(conflictUrl(draft.tenantKey, conflict), { credentials: "same-origin", signal, headers: { accept: "application/json" } }); }
  catch { return { kind: "unavailable" }; }
  if (response.status === 401) return { kind: "expired" };
  if (response.status === 403) return { kind: "forbidden" };
  if ([404, 409, 422].includes(response.status)) return { kind: "changed" };
  if (!response.ok) return { kind: "unavailable" };
  try {
    const connection = parseConflictConnection(await response.json(), draft.tenantKey, conflict);
    return connection.endpoint === draft.draft.endpoint ? { kind: "ready", connection } : { kind: "changed" };
  } catch { return { kind: "changed" }; }
}
