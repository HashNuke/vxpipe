import { directoryPreset, remoteCatalog, isMcpIntegration } from "./remoteDirectory";
/** Storybook-only data. Tool previews and account identities are illustrative. */
export type Authentication = "auto" | "cimd" | "dcr" | "custom" | "none";
export type CustomAuth = "bearer" | "headers" | "basic" | "oauth";
export type Pair = { id: number; name: string; value: string };
export type Preset = {
  id: string;
  name: string;
  description: string;
  endpoint: string;
  auth: Authentication;
  category?: string;
  categories?: string[];
  directoryId?: string;
  directoryRevision?: number;
  logo?: string;
  retired?: boolean;
  customAuth?: CustomAuth;
  scopes?: string;
  headerName?: string;
  icon: "calendar" | "sheet" | "document" | "crm" | "custom";
  docs?: string;
  preview?: boolean;
  setupNotes?: string;
  setupUrl?: string;
};
export const presets: Preset[] = remoteCatalog.integrations.filter(isMcpIntegration).map(entry => directoryPreset(entry, remoteCatalog.directory_id));
export const customPreset: Preset = {
  id: "custom",
  name: "Custom MCP",
  description: "Connect a server by URL",
  endpoint: "",
  auth: "auto",
  icon: "custom",
};
/** Simulated initialize response, not a user-assigned connection alias. */
export const customServerInfo = { name: "office-tools", title: "Office tools" };
export const installationUrl = "https://voice.example.test";
export const callbackUrl = `${installationUrl}/oauth/mcp/callback`;
export const metadataUrl = `${installationUrl}/oauth/client-metadata.json`;
export const authLabels: Record<Authentication, string> = {
  auto: "Discover automatically",
  cimd: "OAuth · CIMD",
  dcr: "OAuth · DCR",
  custom: "Custom authentication",
  none: "No authentication",
};
export type Draft = {
  preset: Preset;
  name: string;
  endpoint: string;
  auth: Authentication;
  customAuth: CustomAuth;
  token: string;
  username: string;
  password: string;
  clientId: string;
  clientSecret: string;
  clientAuth:
    "none" | "client_secret_basic" | "client_secret_post" | "private_key_jwt";
  privateKey: string;
  keyId: string;
  algorithm: string;
  grant: "authorization_code" | "client_credentials";
  endpointMode: "discovery" | "manual";
  issuer: string;
  authorizationUrl: string;
  tokenUrl: string;
  revocationUrl: string;
  registrationUrl: string;
  registrationToken: string;
  scopes: string;
  resource: string;
  audience: string;
  headers: Pair[];
  authorizationParams: Pair[];
  tokenParams: Pair[];
  registrationParams: Pair[];
};
export function draftFor(preset: Preset = customPreset): Draft {
  return {
    preset,
    name: preset.id === "custom" ? "" : preset.name,
    endpoint: preset.endpoint,
    auth: preset.auth,
    customAuth: preset.customAuth ?? (preset.auth === "custom" ? "oauth" : "bearer"),
    token: "",
    username: "",
    password: "",
    clientId: "",
    clientSecret: "",
    clientAuth: "client_secret_basic",
    privateKey: "",
    keyId: "",
    algorithm: "RS256",
    grant: "authorization_code",
    endpointMode: "discovery",
    issuer: "",
    authorizationUrl: "",
    tokenUrl: "",
    revocationUrl: "",
    registrationUrl: "",
    registrationToken: "",
    scopes: preset.scopes ?? "",
    resource: "",
    audience: "",
    headers: preset.headerName ? [{ id: 1, name: preset.headerName, value: "" }] : [],
    authorizationParams: [],
    tokenParams: [],
    registrationParams: [],
  };
}
export type Connection = {
  id: string;
  name: string;
  preset: Preset;
  endpoint: string;
  auth: Authentication;
  account?: string;
  authOptions?: Pick<Draft, "customAuth" | "clientAuth" | "grant">;
  status: "connected" | "reconnect";
  tools: string[];
};
/** Preserve auth choices in the preview without retaining credential values. */
export function draftForConnection(connection: Connection): Draft {
  return { ...draftFor(connection.preset), ...connection.authOptions,
    name: connection.name, endpoint: connection.endpoint, auth: connection.auth };
}
export const connections: Connection[] = [
  {
    id: "reception",
    name: "Cal.com",
    preset: presets[0],
    endpoint: presets[0].endpoint,
    auth: "cimd",
    account: "reception@example.test",
    status: "connected",
    tools: ["get_slots", "get_bookings", "create_booking", "cancel_booking"],
  },
  {
    id: "customers",
    name: "HubSpot",
    preset: presets[3],
    endpoint: presets[3].endpoint,
    auth: "custom",
    account: "Example workspace",
    status: "connected",
    tools: ["search_contacts", "get_contact", "create_contact"],
  },
];
export const scenarios = [
  "services",
  "connected",
  "empty",
  "picker",
  "directory-search-versions",
  "directory-paginated",
  "directory-page-loading",
  "directory-page-error",
  "directory-expanded",
  "directory-loading",
  "directory-unavailable",
  "directory-stale",
  "directory-connections-loading",
  "directory-connections-error",
  "directory-reconnect",
  "directory-ai",
  "directory-telephony",
  "directory-calendar",
  "directory-crm",
  "directory-office",
  "connect-google",
  "connect-deepgram",
  "connect-telnyx",
  "connect-twilio",
  "already-connected-ai",
  "already-connected-mcp",
  "custom",
  "registration-required",
  "discovery-failed",
  "installation-url-required",
  "discovery-no-auth",
  "connected-no-tools",
  "calcom",
  "google-calendar",
  "google-sheets",
  "google-docs",
  "hubspot",
  "calendly",
  "cimd",
  "dcr",
  "custom-oauth",
  "custom-bearer",
  "custom-headers",
  "custom-basic",
  "no-auth",
  "authorizing",
  "checking",
  "connection-error",
  "reconnect",
  "read-only",
] as const;
export type Scenario = (typeof scenarios)[number];
export type Phase =
  "form" | "checking" | "authorize" | "registration" | "discovery-error" | "ready" | "manage" | "disconnect" | null;
export function initialState(scenario: Scenario): {
  phase: Phase;
  draft: Draft;
  selected: string | null;
} {
  const preset =
    presets.find((item) => item.id === scenario) ??
    (scenario === "custom" ||
    scenario.startsWith("custom-") ||
    scenario === "no-auth"
      ? customPreset
      : presets[0]);
  const draft = draftFor(preset);
  if (
    scenario.startsWith("custom-") ||
    ["cimd", "dcr", "no-auth"].includes(scenario)
  ) {
    draft.preset = customPreset;
    draft.name = "Office tools";
    draft.endpoint = "https://office.example.test/mcp";
  }
  if (["registration-required", "discovery-failed", "installation-url-required", "discovery-no-auth"].includes(scenario)) {
    draft.preset = customPreset;
    draft.name = "Office tools";
    draft.endpoint = "https://office.example.test/mcp";
    draft.auth = "auto";
    draft.customAuth = "bearer";
  }
  if (scenario.startsWith("custom-")) {
    draft.auth = "custom";
    draft.customAuth = scenario.slice(7) as CustomAuth;
  }
  if (scenario === "custom-headers")
    draft.headers = [{ id: 1, name: "X-API-Key", value: "" }];
  if (scenario === "cimd" || scenario === "dcr") draft.auth = scenario;
  if (scenario === "no-auth") draft.auth = "none";
  const phase =
    scenario === "registration-required" ? "registration" :
    scenario === "discovery-failed" ? "discovery-error" :
    scenario === "connected-no-tools" ? "ready" :
    ["services", "connected", "empty", "read-only", "picker"].includes(scenario) ||
    scenario.startsWith("directory-") ||
    scenario.startsWith("already-connected-") ||
    scenario.startsWith("connect-")
      ? null
      : scenario === "reconnect"
        ? "manage"
        : scenario === "authorizing"
          ? "authorize"
          : scenario === "checking"
            ? "checking"
            : "form";
  return {
    phase,
    draft,
    selected: ["reconnect", "connected-no-tools"].includes(scenario) ? "reception" : null,
  };
}
