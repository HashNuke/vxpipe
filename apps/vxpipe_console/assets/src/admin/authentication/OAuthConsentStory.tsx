import { useState } from "react";
import { AuthenticationStory } from "../stories/AuthenticationStory";
import { NavigationJourney } from "../navigation/NavigationJourney";
import { OAuthConsent, type ClientMetadata, type ConsentStep } from "./OAuthConsent";
import { Button } from "../Button";
import type { Theme } from "./types";
type Step = ConsentStep | "connections" | "console" | "client";
type Access = "assigned" | "all-tenants" | "empty";

// Branding comes from the supplied CIMD example; all account/authority data is synthetic.
const codex: ClientMetadata = {
  client_id: "https://chatgpt.com/oauth/codex/client.json",
  client_name: "Codex",
  client_uri: "https://chatgpt.com/codex",
  logo_uri: "https://persistent.oaistatic.com/sonic/misc/openai-logo.png",
};
const dcr: ClientMetadata = {
  client_id: "example-registered-client",
  client_name: "Research assistant",
};
const grants = ["calls.read", "call_specs.read", "call_specs.write"];
const resource = "https://voice.example.test/mcp";
export type OAuthConsentStoryProps = {
  theme?: Theme;
  initialStep?: Step;
  clientKind?: "cimd" | "dcr";
  branding?: "provided" | "missing" | "broken";
  access?: Access;
  longContent?: boolean;
};

/** Design review only: no authorization requests, credentials, or external redirects. */
export function OAuthConsentStory({
  theme = "dark", initialStep = "consent", clientKind = "cimd",
  branding = "provided", access = "assigned", longContent = false,
}: OAuthConsentStoryProps) {
  const [step, setStep] = useState(initialStep);
  const base = clientKind === "cimd" ? codex : dcr;
  const client = {
    ...base,
    client_name: longContent ? "Research and operations assistant for the international customer support team" : base.client_name,
    logo_uri: branding === "missing" ? undefined : branding === "broken" ? "https://example.invalid/missing-logo.png" : base.logo_uri,
  };
  if (step === "connections") return <AuthenticationStory theme={theme} initialPath="/account/connections" followLocation={false} />;
  if (step === "console") return <NavigationJourney theme={theme} />;
  if (step === "client") return <div className="vx-admin oauth-preview" data-theme={theme}><main className="oauth-preview-main">
    <h1>{client.client_name}</h1><p role="status">Returned to {client.client_name}</p>
    <Button onClick={() => setStep("consent")}>Review another request</Button>
  </main></div>;
  const redirectUri = clientKind === "cimd" ? "http://127.0.0.1:1455/callback" : "https://client.example.test/oauth/callback";
  return <OAuthConsent theme={theme} step={step} requestId="storybook" csrfToken="storybook"
    consent={{ ...client, user_email: "owner@example.test", resource,
      redirect_uri: redirectUri,
      grant_lifetime_seconds: 2592000,
      authority: { grants: access === "empty" ? [] : grants,
        all_tenant_actions: access === "all-tenants" ? grants : [],
        assigned_tenants: access === "assigned" ? { Demo: "read_write" } : {},
      },
    }} onDecision={() => setStep("client")} onNavigate={setStep} />;
}
