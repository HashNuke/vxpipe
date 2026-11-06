export type McpDiscovery = {
  endpoint: string; revision: string;
  outcome: "anonymous" | "oauth" | "issuer_required" | "partial" | "unknown" | "unsupported_oauth";
  suggestedMethod: "none" | "cimd" | "dcr" | "own_client" | null;
  serverName?: string; issuers: string[];
  oauth: Record<string, unknown> | null;
  resource: Record<string, unknown> | null;
  supportedGrants: Array<"authorization_code" | "client_credentials">;
  oauthClient: { callbackUrl: string; clientId: string } | null;
};

export function validMcpUrl(value: string): boolean {
  if (value.length > 2048 || Array.from(value).some(char => char.charCodeAt(0) <= 32 || char.charCodeAt(0) === 127)) return false;
  try { const url = new URL(value); return url.protocol === "https:" && !!url.hostname && !url.username && !url.password && !url.hash; }
  catch { return false; }
}
function object(value: unknown): value is Record<string, unknown> { return !!value && typeof value === "object" && !Array.isArray(value); }
export function parseMcpDiscovery(body: unknown, endpoint: string, revision: string): McpDiscovery {
  if (!object(body) || !object(body.discovery)) throw new Error("Invalid discovery result");
  const value = body.discovery;
  if (value.endpoint !== endpoint || value.revision !== revision ||
    !["anonymous", "oauth", "issuer_required", "partial", "unknown", "unsupported_oauth"].includes(String(value.outcome))) throw new Error("Mismatched discovery result");
  const outcome = value.outcome as McpDiscovery["outcome"];
  const method = value.suggested_method ?? null;
  if (![null, "none", "cimd", "dcr", "own_client"].includes(method as string | null) ||
    (method === "none" && outcome !== "anonymous") || (outcome === "anonymous" && method !== "none")) throw new Error("Invalid authentication suggestion");
  const issuers = value.issuers ?? [];
  if (!Array.isArray(issuers) || issuers.length > 8 || !issuers.every(item => typeof item === "string" && validMcpUrl(item))) throw new Error("Invalid issuers");
  const grants = value.supported_grants ?? [];
  if (!Array.isArray(grants) || grants.length > 2 || !grants.every(value => value === "authorization_code" || value === "client_credentials")) throw new Error("Invalid supported grants");
  let oauthClient: McpDiscovery["oauthClient"] = null;
  if (value.oauth_client !== null && value.oauth_client !== undefined) {
    const client = value.oauth_client;
    if (!object(client) || typeof client.callback_url !== "string" || typeof client.client_id !== "string" ||
      !validMcpUrl(client.callback_url) || !validMcpUrl(client.client_id)) throw new Error("Invalid installation identity");
    const callback = new URL(client.callback_url), metadata = new URL(client.client_id);
    if (callback.origin !== metadata.origin || callback.pathname !== "/oauth/mcp/callback" ||
      metadata.pathname !== "/oauth/client-metadata.json" || callback.search || metadata.search) throw new Error("Invalid installation identity");
    oauthClient = { callbackUrl: client.callback_url, clientId: client.client_id };
  }
  return { endpoint, revision, outcome, suggestedMethod: method as McpDiscovery["suggestedMethod"], issuers,
    supportedGrants: grants as McpDiscovery["supportedGrants"], oauthClient,
    serverName: typeof value.server_name === "string" ? value.server_name.slice(0, 200) : undefined,
    oauth: object(value.oauth) ? value.oauth : null, resource: object(value.resource) ? value.resource : null };
}
