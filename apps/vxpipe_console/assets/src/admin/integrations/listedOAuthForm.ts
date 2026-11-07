import type { McpDirectoryEntry, McpListingReference } from "./listedMcp";
import { validMcpUrl, type McpDiscovery } from "./mcpDiscoveryApi";
import { oauthOptions, oauthRequest, type OAuthMethod, type OAuthValues } from "./oauthForm";

export function listedOAuthMethod(entry: McpDirectoryEntry, discovery: McpDiscovery | null): OAuthMethod | "" {
  if (entry.authentication.type !== "oauth2" || discovery?.outcome !== "oauth" || !discovery.supportedGrants.includes("authorization_code")) return "";
  if (discovery.oauthRegistration) return discovery.oauthRegistration.method;
  if (entry.authentication.registration === "preregistered" || !discovery.resource) return "own_client";
  const methods = oauthOptions(discovery, "authorization_code").methods;
  const cimd = discovery.oauth?.client_id_metadata_document_supported === true && methods.includes("none");
  const registration = discovery.oauth?.registration_endpoint;
  const dcr = typeof registration === "string" && validMcpUrl(registration) && methods.some(method => method !== "private_key_jwt");
  if (entry.authentication.registration === "dcr" && dcr) return "dcr";
  return cimd ? "cimd" : dcr ? "dcr" : "own_client";
}

export function listedOAuthRequest(method: OAuthMethod, revision: string, values: OAuthValues, issuer?: string, listing?: McpListingReference) {
  const base = { ...(listing ? { listing } : {}), revision, ...(issuer ? { issuer } : {}) };
  if (method === "cimd") return base;
  if (method === "dcr") return { ...base, ...(values.initialAccessToken ? { initial_access_token: values.initialAccessToken } : {}) };
  const credentials = oauthRequest(method, values.resource, revision, { ...values, grant: "authorization_code" }, issuer).credentials ?? {};
  const fields = ["client_id", "client_auth_method", "client_secret", "private_key", "algorithm", "key_id"];
  return { ...base, credentials: Object.fromEntries(Object.entries(credentials).filter(([key]) => fields.includes(key))) };
}
