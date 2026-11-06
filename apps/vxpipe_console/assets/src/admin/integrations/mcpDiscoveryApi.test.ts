import { expect, test } from "vitest";
import { parseMcpDiscovery } from "./mcpDiscoveryApi";

const endpoint = "https://mcp.example.test/mcp";
const discovery = {
  endpoint, revision: "draft", outcome: "oauth", suggested_method: "cimd",
  supported_grants: ["authorization_code", "client_credentials"],
  issuers: ["https://auth.example.test"],
  oauth: { issuer: "https://auth.example.test", token_endpoint: "https://auth.example.test/token" },
  oauth_client: { callback_url: "https://console.example.test/oauth/mcp/callback", client_id: "https://console.example.test/oauth/client-metadata.json" },
};

test("discovery carries supported grants and the installation's exact callback identity", () => {
  expect(parseMcpDiscovery({ discovery }, endpoint, "draft")).toMatchObject({
    supportedGrants: ["authorization_code", "client_credentials"],
    oauthClient: { callbackUrl: discovery.oauth_client.callback_url, clientId: discovery.oauth_client.client_id },
  });
});

test.each([
  { ...discovery, supported_grants: ["implicit"] },
  { ...discovery, oauth_client: { ...discovery.oauth_client, callback_url: "https://other.example.test/oauth/mcp/callback" } },
  { ...discovery, oauth_client: { ...discovery.oauth_client, callback_url: "javascript:alert(1)" } },
])("rejects invalid grant/callback metadata", value => {
  expect(() => parseMcpDiscovery({ discovery: value }, endpoint, "draft")).toThrow();
});

test("missing public installation metadata does not invent a callback", () => {
  expect(parseMcpDiscovery({ discovery: { ...discovery, oauth_client: null } }, endpoint, "draft").oauthClient).toBeNull();
});
