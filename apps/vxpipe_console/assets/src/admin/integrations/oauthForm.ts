import type { McpDiscovery } from "./mcpDiscoveryApi";
import { validMcpUrl } from "./mcpDiscoveryApi";

export type OAuthMethod = "cimd" | "dcr" | "own_client";
export type OAuthGrant = "authorization_code" | "client_credentials";
export type ClientAuthentication = "none" | "client_secret_basic" | "client_secret_post" | "private_key_jwt";
export type OAuthPair = { id: number; name: string; value: string };
export type OAuthValues = {
  grant: OAuthGrant; clientAuth: ClientAuthentication; clientId: string; clientSecret: string;
  initialAccessToken: string; privateKey: string; keyId: string; algorithm: string;
  authorizationUrl: string; tokenUrl: string; revocationUrl: string; scopes: string; resource: string; audience: string;
  authorizationParams: OAuthPair[]; tokenParams: OAuthPair[]; headers: OAuthPair[];
};
const clientMethods: ClientAuthentication[] = ["none", "client_secret_basic", "client_secret_post", "private_key_jwt"];
const algorithms = ["RS256", "ES256", "PS256"];
const string = (value: unknown) => typeof value === "string" ? value : "";
const strings = (value: unknown): string[] => Array.isArray(value) && value.every(item => typeof item === "string") ? value : [];

export function oauthOptions(discovery: McpDiscovery | null, grant: OAuthGrant) {
  const oauth = discovery?.oauth;
  const advertised = oauth?.token_endpoint_auth_methods_supported === undefined ? ["client_secret_basic"] : strings(oauth.token_endpoint_auth_methods_supported);
  const signing = algorithms.filter(value => strings(oauth?.token_endpoint_auth_signing_alg_values_supported).includes(value));
  return {
    grants: discovery?.supportedGrants ?? [],
    methods: clientMethods.filter(method => advertised.includes(method) && (grant !== "client_credentials" || method !== "none") && (method !== "private_key_jwt" || signing.length > 0)),
    algorithms: signing,
  };
}

export function oauthDefaults(endpoint: string, discovery: McpDiscovery | null): OAuthValues {
  const grant = discovery?.supportedGrants[0] ?? "authorization_code";
  const choices = oauthOptions(discovery, grant);
  const resource = discovery?.resource;
  return {
    grant, clientAuth: choices.methods[0] ?? "client_secret_basic", clientId: "", clientSecret: "", initialAccessToken: "",
    privateKey: "", keyId: "", algorithm: choices.algorithms[0] ?? "RS256",
    authorizationUrl: string(discovery?.oauth?.authorization_endpoint), tokenUrl: string(discovery?.oauth?.token_endpoint),
    revocationUrl: string(discovery?.oauth?.revocation_endpoint),
    scopes: string(resource?.challenge_scope) || strings(resource?.scopes_supported).join(" "),
    resource: endpoint, audience: "", authorizationParams: [], tokenParams: [], headers: [],
  };
}

type OAuthRequest = {
  endpoint: string; revision: string; auth_method: OAuthMethod; issuer?: string;
  initial_access_token?: string; credentials?: Record<string, unknown>;
};
const pairs = (values: OAuthPair[]) => values.map(({ name, value }) => ({ name, value }));
export function oauthRequest(method: OAuthMethod, endpoint: string, revision: string, values: OAuthValues, issuer?: string): OAuthRequest {
  const base = { endpoint, revision, auth_method: method, ...(issuer ? { issuer } : {}) };
  if (method === "cimd") return base;
  if (method === "dcr") return { ...base, ...(values.initialAccessToken ? { initial_access_token: values.initialAccessToken } : {}) };
  const credentials: Record<string, unknown> = {
    grant_type: values.grant, client_id: values.clientId, client_auth_method: values.clientAuth,
    scopes: values.scopes.trim() ? values.scopes.trim().split(/\s+/) : [], resource: values.resource,
    token_parameters: pairs(values.tokenParams), headers: pairs(values.headers),
    ...(values.tokenUrl ? { token_endpoint: values.tokenUrl } : {}),
    ...(values.revocationUrl ? { revocation_endpoint: values.revocationUrl } : {}),
    ...(values.audience ? { audience: values.audience } : {}),
  };
  if (values.grant === "authorization_code") {
    if (values.authorizationUrl) credentials.authorization_endpoint = values.authorizationUrl;
    credentials.authorization_parameters = pairs(values.authorizationParams);
  }
  if (values.clientAuth === "client_secret_basic" || values.clientAuth === "client_secret_post") credentials.client_secret = values.clientSecret;
  if (values.clientAuth === "private_key_jwt") {
    credentials.private_key = values.privateKey;
    credentials.algorithm = values.algorithm;
    if (values.keyId) credentials.key_id = values.keyId;
  }
  return { ...base, credentials };
}

/** Early form feedback; the backend always rediscovers and validates before sending credentials. */
export function oauthProblem(method: OAuthMethod, values: OAuthValues, discovery: McpDiscovery | null): string | null {
  if (discovery?.outcome === "unsupported_oauth") return "This server does not support the OAuth security requirements needed to connect.";
  if (discovery?.outcome !== "oauth") return "Discover this server's OAuth settings before connecting.";
  const grant = method === "own_client" ? values.grant : "authorization_code";
  const choices = oauthOptions(discovery, grant);
  if (!choices.grants.includes(grant)) return "Choose a grant supported by this server.";
  if (grant === "authorization_code" && !discovery.oauthClient) return "Set a public HTTPS Installation URL before connecting with browser OAuth.";
  if (method === "cimd") return discovery.oauth?.client_id_metadata_document_supported === true && choices.methods.includes("none") ? null : "This server does not advertise CIMD support.";
  if (method === "dcr") return validMcpUrl(string(discovery.oauth?.registration_endpoint)) && choices.methods.some(value => value !== "private_key_jwt") ? null : "This server does not advertise supported dynamic registration.";
  if (!choices.methods.includes(values.clientAuth)) return "Choose client authentication supported by this server and grant.";
  if (!values.clientId.trim()) return "Enter the registered client ID.";
  if (["client_secret_basic", "client_secret_post"].includes(values.clientAuth) && !values.clientSecret) return "Enter the client secret.";
  if (values.clientAuth === "private_key_jwt") {
    if (!choices.algorithms.includes(values.algorithm)) return "Choose a signing algorithm advertised by this server.";
    if (!values.privateKey.trim()) return "Enter the private key for this OAuth client.";
  }
  if (values.resource !== discovery.endpoint) return "Resource must match the MCP server URL.";
  const endpoints = [values.tokenUrl, values.revocationUrl, ...(grant === "authorization_code" ? [values.authorizationUrl] : [])];
  if (endpoints.some(value => value && !validMcpUrl(value))) return "Enter valid HTTPS OAuth endpoint URLs.";
  const activePairs = [...values.tokenParams, ...values.headers, ...(grant === "authorization_code" ? values.authorizationParams : [])];
  if (activePairs.some(pair => !pair.name || !pair.value)) return "Complete or remove empty request parameters and headers.";
  return null;
}
