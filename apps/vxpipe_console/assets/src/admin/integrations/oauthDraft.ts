import { validMcpUrl } from "./mcpDiscoveryApi";
import type { ClientAuthentication, OAuthMethod } from "./oauthForm";

export type OAuthDraft = {
  endpoint: string; method: OAuthMethod; issuer?: string; clientAuth?: ClientAuthentication; generation?: number;
};
export type OAuthDraftIdentity = { actorId: string; tenantKey: string; attemptId: string };
export type StoredOAuthDraft = OAuthDraftIdentity & { connectionId: string; returnTo: string; createdAt: number; draft: OAuthDraft };
type StoragePort = Pick<Storage, "getItem" | "setItem" | "removeItem">;
const key = "vxpipe.mcp.oauth";
const fields = ["endpoint", "method", "issuer", "clientAuth", "generation"];
const record = (value: unknown): value is Record<string, unknown> => !!value && typeof value === "object" && !Array.isArray(value);
const id = (value: unknown): value is string => typeof value === "string" && /^[a-zA-Z0-9_-]{1,128}$/.test(value);
function publicUrl(value: unknown): value is string {
  return typeof value === "string" && validMcpUrl(value) && !new URL(value).search;
}
function returnLocation(value: unknown, tenant: string): value is string {
  if (typeof value !== "string" || value.length > 16384 || !value.startsWith("/") || value.startsWith("//")) return false;
  const url = new URL(value, "https://console.invalid");
  const base = `/t/${encodeURIComponent(tenant)}/services`;
  if (url.origin !== "https://console.invalid" || url.hash ||
    !(url.pathname === base || (url.pathname.startsWith(`${base}/`) && /^[a-z][a-z0-9-]{0,63}$/.test(url.pathname.slice(base.length + 1))))) return false;
  return [...url.searchParams.keys()].every(name => {
    const text = url.searchParams.get(name) ?? "";
    return ["q", "cursor"].includes(name) && url.searchParams.getAll(name).length === 1 &&
      text.length <= (name === "q" ? 200 : 2048) && (name !== "cursor" || !!text) &&
      !Array.from(text).some(char => char.charCodeAt(0) < 32 || char.charCodeAt(0) === 127);
  });
}
function sanitize(value: unknown, createdAt: number, strict: boolean): StoredOAuthDraft | null {
  if (!record(value) || !id(value.actorId) || !id(value.tenantKey) || !id(value.attemptId) || !id(value.connectionId) ||
    !returnLocation(value.returnTo, value.tenantKey) || !record(value.draft) || !Number.isSafeInteger(createdAt) || createdAt < 0) return null;
  const draft = value.draft;
  if (!publicUrl(draft.endpoint) || !["cimd", "dcr", "own_client"].includes(String(draft.method)) ||
    (draft.issuer !== undefined && !publicUrl(draft.issuer)) ||
    (draft.clientAuth !== undefined && !["none", "client_secret_basic", "client_secret_post", "private_key_jwt"].includes(String(draft.clientAuth))) ||
    (draft.generation !== undefined && (!Number.isSafeInteger(draft.generation) || Number(draft.generation) < 1)) ||
    (strict && (Object.keys(draft).some(name => !fields.includes(name)) || Object.keys(value).some(name => !["actorId", "tenantKey", "attemptId", "connectionId", "returnTo", "createdAt", "draft"].includes(name))))) return null;
  return {
    actorId: value.actorId, tenantKey: value.tenantKey, attemptId: value.attemptId, connectionId: value.connectionId,
    returnTo: value.returnTo, createdAt,
    draft: { endpoint: draft.endpoint, method: draft.method as OAuthMethod,
      ...(draft.issuer ? { issuer: String(draft.issuer) } : {}),
      ...(draft.clientAuth ? { clientAuth: draft.clientAuth as ClientAuthentication } : {}),
      ...(draft.generation ? { generation: Number(draft.generation) } : {}),
    },
  };
}

/** This optional tab-local draft is never authority to complete OAuth or use a connection. */
export function saveOAuthDraft(value: unknown, now = Date.now(), storage?: StoragePort): boolean {
  try {
    const target = storage ?? window.sessionStorage;
    target.removeItem(key);
    const draft = sanitize(value, now, false);
    if (!draft) return false;
    const encoded = JSON.stringify(draft);
    if (encoded.length > 8192) return false;
    target.setItem(key, encoded);
    return true;
  } catch { return false; }
}

export function takeOAuthDraft(identity: OAuthDraftIdentity, now = Date.now(), storage?: StoragePort): StoredOAuthDraft | null {
  try {
    const target = storage ?? window.sessionStorage;
    const encoded = target.getItem(key);
    if (!encoded) return null;
    if (encoded.length > 8192) { target.removeItem(key); return null; }
    let value: unknown;
    try { value = JSON.parse(encoded); } catch { target.removeItem(key); return null; }
    const draft = sanitize(value, record(value) && typeof value.createdAt === "number" ? value.createdAt : NaN, true);
    if (!draft || draft.createdAt > now || now - draft.createdAt > 300_000) { target.removeItem(key); return null; }
    if (draft.actorId !== identity.actorId || draft.tenantKey !== identity.tenantKey || draft.attemptId !== identity.attemptId) return null;
    target.removeItem(key);
    return draft;
  } catch { return null; }
}
