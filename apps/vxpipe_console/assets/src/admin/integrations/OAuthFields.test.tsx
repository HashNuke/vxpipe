import { useState } from "react";
import { cleanup, fireEvent, render, screen, within } from "@testing-library/react";
import { afterEach, expect, test } from "vitest";
import { OAuthFields } from "./OAuthFields";
import { oauthDefaults, type OAuthMethod } from "./oauthForm";
import type { McpDiscovery } from "./mcpDiscoveryApi";

afterEach(cleanup);
const discovery: McpDiscovery = {
  endpoint: "https://mcp.example.test/mcp", revision: "1", outcome: "oauth", suggestedMethod: "own_client",
  issuers: ["https://auth.example.test"], supportedGrants: ["authorization_code", "client_credentials"], resource: null,
  oauthClient: { callbackUrl: "https://installation.example.test/oauth/mcp/callback", clientId: "https://installation.example.test/oauth/client-metadata.json" },
  oauth: { token_endpoint_auth_methods_supported: ["none", "client_secret_basic", "private_key_jwt"], token_endpoint_auth_signing_alg_values_supported: ["RS256"] },
};
function Form({ method }: { method: OAuthMethod }) {
  const [values, setValues] = useState(oauthDefaults(discovery.endpoint, discovery));
  return <OAuthFields method={method} values={values} discovery={discovery} issuer="https://auth.example.test" onIssuerChange={() => undefined} onChange={patch => setValues(current => ({ ...current, ...patch }))} />;
}

test.each(["cimd", "dcr"] as const)("%s hides managed OAuth configuration and manual parameter editors", method => {
  render(<Form method={method} />);
  expect(screen.queryByLabelText("Client ID")).not.toBeInTheDocument();
  expect(screen.queryByLabelText("Callback URL")).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "OAuth endpoints and scopes" })).not.toBeInTheDocument();
  expect(screen.queryByRole("button", { name: "Additional parameters" })).not.toBeInTheDocument();
  if (method === "dcr") expect(screen.getByLabelText("Initial registration token")).toHaveAttribute("type", "password");
  else expect(screen.queryByLabelText("Initial registration token")).not.toBeInTheDocument();
});

test("Own-client uses installation callback metadata and hides browser-only fields for machine grants", () => {
  render(<Form method="own_client" />);
  expect(screen.getByLabelText("Callback URL")).toHaveValue(discovery.oauthClient!.callbackUrl);
  fireEvent.click(screen.getByRole("button", { name: "OAuth endpoints and scopes" }));
  fireEvent.click(screen.getByRole("button", { name: "Additional parameters" }));
  expect(screen.getByLabelText("Authorization URL")).toBeVisible();
  expect(screen.getByRole("group", { name: "Authorization request" })).toBeVisible();
  fireEvent.change(screen.getByLabelText("Grant type"), { target: { value: "client_credentials" } });
  expect(screen.queryByLabelText("Callback URL")).not.toBeInTheDocument();
  expect(screen.queryByLabelText("Authorization URL")).not.toBeInTheDocument();
  expect(screen.queryByRole("group", { name: "Authorization request" })).not.toBeInTheDocument();
  expect(screen.getByLabelText("Client authentication")).toHaveValue("client_secret_basic");
  expect(within(screen.getByLabelText("Client authentication")).queryByRole("option", { name: "None · public client" })).not.toBeInTheDocument();
  fireEvent.change(screen.getByLabelText("Client authentication"), { target: { value: "private_key_jwt" } });
  expect(screen.getByLabelText("Private key (PEM)")).toBeVisible();
  expect(within(screen.getByLabelText("Signing algorithm")).getAllByRole("option").map(option => option.textContent)).toEqual(["RS256"]);
  expect(screen.queryByLabelText("Client secret")).not.toBeInTheDocument();
});
