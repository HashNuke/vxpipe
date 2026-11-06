import { expect, test } from "vitest";
import type { McpDiscovery } from "./mcpDiscoveryApi";
import { oauthDefaults, oauthOptions, oauthProblem, oauthRequest } from "./oauthForm";

const endpoint = "https://mcp.example.test/mcp";
const discovery: McpDiscovery = {
  endpoint, revision: "1", outcome: "oauth", suggestedMethod: "cimd", issuers: ["https://auth.example.test"],
  supportedGrants: ["authorization_code", "client_credentials"],
  oauthClient: { callbackUrl: "https://console.example.test/oauth/mcp/callback", clientId: "https://console.example.test/oauth/client-metadata.json" },
  resource: { challenge_scope: "calendar.read", scopes_supported: ["calendar.write"] },
  oauth: { issuer: "https://auth.example.test", authorization_endpoint: "https://auth.example.test/authorize", token_endpoint: "https://auth.example.test/token",
    client_id_metadata_document_supported: true, registration_endpoint: "https://auth.example.test/register",
    token_endpoint_auth_methods_supported: ["none", "client_secret_basic", "private_key_jwt"],
    token_endpoint_auth_signing_alg_values_supported: ["RS256", "HS256"] },
};

test("prefills only actual metadata, honors challenge scopes and exposes advertised choices", () => {
  const values = oauthDefaults(endpoint, discovery);
  expect(values).toMatchObject({ grant: "authorization_code", clientAuth: "none", scopes: "calendar.read", resource: endpoint,
    authorizationUrl: "https://auth.example.test/authorize", tokenUrl: "https://auth.example.test/token" });
  expect(oauthOptions(discovery, "client_credentials")).toEqual({ grants: discovery.supportedGrants, methods: ["client_secret_basic", "private_key_jwt"], algorithms: ["RS256"] });
  expect(oauthDefaults(endpoint, null).tokenUrl).toBe("");
});

test("managed methods ignore all manual fields and DCR sends only its optional initial token", () => {
  const values = { ...oauthDefaults(endpoint, discovery), initialAccessToken: "initial-token", clientId: "ignored", clientSecret: "ignored",
    tokenUrl: "invalid", headers: [{ id: 1, name: "X-Extra", value: "ignored" }] };
  expect(oauthRequest("cimd", endpoint, "1", values)).toEqual({ endpoint, revision: "1", auth_method: "cimd" });
  expect(oauthRequest("dcr", endpoint, "1", values)).toEqual({ endpoint, revision: "1", auth_method: "dcr", initial_access_token: "initial-token" });
  expect(oauthProblem("cimd", values, discovery)).toBeNull();
});

test("public clients never send stale secret/key fields and machine grants never send browser fields", () => {
  const values = { ...oauthDefaults(endpoint, discovery), clientId: "registered", clientSecret: "old-secret", privateKey: "old-key", keyId: "old-kid",
    authorizationParams: [{ id: 1, name: "prompt", value: "consent" }] };
  const code = oauthRequest("own_client", endpoint, "1", values);
  expect(code.credentials).not.toHaveProperty("client_secret");
  expect(code.credentials).not.toHaveProperty("private_key");
  const machine = oauthRequest("own_client", endpoint, "1", { ...values, grant: "client_credentials", clientAuth: "client_secret_basic" });
  expect(machine.credentials).toMatchObject({ client_secret: "old-secret", grant_type: "client_credentials" });
  expect(machine.credentials).not.toHaveProperty("authorization_endpoint");
  expect(machine.credentials).not.toHaveProperty("authorization_parameters");
  expect(machine.credentials).not.toHaveProperty("private_key");
});

test("browser flows require installation identity while machine grants require supported confidential authentication", () => {
  const missingCallback = { ...discovery, oauthClient: null };
  const values = { ...oauthDefaults(endpoint, discovery), clientId: "registered", clientSecret: "synthetic" };
  expect(oauthProblem("cimd", values, missingCallback)).toMatch(/Installation URL/);
  expect(oauthProblem("own_client", { ...values, grant: "client_credentials", clientAuth: "client_secret_basic" }, missingCallback)).toBeNull();
  expect(oauthProblem("own_client", { ...values, grant: "client_credentials", clientAuth: "none" }, discovery)).toMatch(/authentication/);
  expect(oauthProblem("own_client", { ...values, clientAuth: "private_key_jwt", privateKey: "synthetic", algorithm: "ES256" }, discovery)).toMatch(/algorithm/);
});
