import { useEffect, useRef, useState } from "react";
import { ArrowRight, Check, ChevronRight, CircleCheck, CircleSlash, Clock3, Globe, Plug, ShieldCheck } from "lucide-react";
import { Button } from "../Button";
import { AuthenticationStory } from "../stories/AuthenticationStory";
import { NavigationJourney } from "../navigation/NavigationJourney";
import type { Theme } from "./types";
import "./oauthConsentStory.css";

type ClientMetadata = {
  client_id: string;
  client_name: string;
  client_uri?: string;
  logo_uri?: string;
};
type Step = "consent" | "allowed" | "denied" | "unavailable" | "connections" | "console";
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
const grants = [
  { key: "calls.read", label: "Read calls", detail: "View calls and their details." },
  { key: "call_specs.read", label: "Read call specs", detail: "View your voice-agent configurations." },
  { key: "call_specs.write", label: "Write call specs", detail: "Create and change voice-agent configurations." },
];
const resource = "https://voice.example.test/mcp";

function httpsUrl(value?: string): string | undefined {
  if (!value) return undefined;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !url.username && !url.password ? url.href : undefined;
  } catch { return undefined; }
}

function ClientLogo({ client }: { client: ClientMetadata }) {
  const [failed, setFailed] = useState(false);
  const logo = httpsUrl(client.logo_uri);
  return (
    <span className={`oauth-preview-logo${logo && !failed ? " oauth-preview-logo-image" : ""}`}>
      {logo && !failed
        ? <img src={logo} alt={`${client.client_name} logo`} width={36} height={36} referrerPolicy="no-referrer" onError={() => setFailed(true)} />
        : <Plug size={28} role="img" aria-label="Client icon" />}
    </span>
  );
}

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
  const heading = useRef<HTMLHeadingElement>(null);
  const didNavigate = useRef(false);
  const base = clientKind === "cimd" ? codex : dcr;
  const client = {
    ...base,
    client_name: longContent ? "Research and operations assistant for the international customer support team" : base.client_name,
    logo_uri: branding === "missing" ? undefined : branding === "broken" ? "https://example.invalid/missing-logo.png" : base.logo_uri,
  };
  const website = httpsUrl(client.client_uri);
  const callback = clientKind === "cimd" ? "http://localhost:1455/callback" : "https://client.example.test/oauth/callback";
  const permissions = access === "empty" ? [] : grants;

  useEffect(() => {
    if (didNavigate.current) heading.current?.focus();
  }, [step]);

  function navigate(next: Step) {
    didNavigate.current = true;
    setStep(next);
  }

  if (step === "connections") return <AuthenticationStory theme={theme} initialPath="/account/connections" followLocation={false} />;
  if (step === "console") return <NavigationJourney theme={theme} />;

  return (
    <div className="vx-admin oauth-preview" data-theme={theme}>
      <header className="oauth-preview-header">
        <span className="oauth-preview-wordmark">Vxpipe</span>
        <span>MCP connection</span>
      </header>
      <main className={`oauth-preview-main${step === "allowed" || step === "denied" ? " oauth-preview-outcome" : ""}`}>
        {step === "consent" ? <>
          <div className="oauth-preview-client">
            <ClientLogo key={`${client.client_id}-${client.logo_uri}`} client={client} />
            <ArrowRight size={18} aria-hidden />
            <span className="oauth-preview-vx" aria-label="Vxpipe">Vx</span>
          </div>
          <h1 ref={heading} tabIndex={-1}>Connect {client.client_name} to Vxpipe?</h1>
          <p className="oauth-preview-lead">This app wants to use the Vxpipe API on your behalf.</p>
          {website ? <a className="oauth-preview-website" href={website} target="_blank" rel="noopener noreferrer" referrerPolicy="no-referrer">
            <Globe size={15} aria-hidden /> {website.replace("https://", "")}
          </a> : null}

          <div className="oauth-preview-account">
            <span>Signed in as</span>
            <strong>owner@example.test</strong>
          </div>

          <section className="oauth-preview-access" aria-labelledby="oauth-access-heading">
            <h2 id="oauth-access-heading">Access you’re allowing</h2>
            {permissions.length ? <ul className="oauth-preview-permissions">
              {permissions.map((permission) => <li key={permission.key}>
                <Check size={17} aria-hidden />
                <div><h3>{permission.label}</h3><p>{permission.detail}</p></div>
              </li>)}
            </ul> : <p className="oauth-preview-empty"><strong>No action permissions available</strong><br />Your account currently has no actions to delegate to this client.</p>}
            {access !== "empty" ? <div className="oauth-preview-scope">
              <h3>{access === "all-tenants" ? "All tenants, including future tenants" : "For your assigned tenant"}</h3>
              <p>{access === "all-tenants" ? "The permissions above apply across this installation." : <><strong>Demo</strong><span>Read and write</span></>}</p>
            </div> : null}
          </section>

          <details className="oauth-preview-details">
            <summary>Connection details <ChevronRight size={16} aria-hidden /></summary>
            <dl>
              <dt>Client ID{clientKind === "cimd" ? " · metadata document" : ""}</dt><dd>{client.client_id}</dd>
              <dt>Vxpipe API</dt><dd>{resource}</dd>
              <dt>Return address</dt><dd>{callback}</dd>
              {clientKind === "cimd" ? <><dt>Local app callback</dt><dd>Returns to {client.client_name} on this device.</dd></> : null}
              <dt>Exact permissions</dt><dd>{permissions.length ? permissions.map((permission) => <code key={permission.key}>{permission.key}</code>) : "None"}</dd>
            </dl>
          </details>

          <div className="oauth-preview-limits">
            <p><Clock3 size={16} aria-hidden /><span>Access ends after <strong>30 days</strong>. Changes to your role or access require a new connection.</span></p>
            <p><ShieldCheck size={16} aria-hidden /><span>Revoke access anytime in <a href="/account/connections" onClick={(event) => { event.preventDefault(); navigate("connections"); }}>Settings → Your connections</a>.</span></p>
          </div>
          <p className="oauth-preview-trust">Only allow this if you started the connection and trust {client.client_name}.</p>
          <div className="oauth-preview-actions">
            <Button onClick={() => navigate("denied")}>Deny</Button>
            <Button className="oauth-preview-allow" onClick={() => navigate("allowed")}>Allow connection <ArrowRight size={16} aria-hidden /></Button>
          </div>
          <p className="oauth-preview-return">Either choice returns you to {client.client_name}.</p>
        </> : step === "unavailable" ? <>
          <CircleSlash size={32} className="oauth-preview-status" aria-hidden />
          <h1 ref={heading} tabIndex={-1}>This request can’t be completed</h1>
          <p className="oauth-preview-lead">The request may have expired or already been used. Start a new connection from {client.client_name}.</p>
          <div className="oauth-preview-outcome-actions"><Button onClick={() => navigate("console")}>Back to Vxpipe <ArrowRight size={16} aria-hidden /></Button></div>
        </> : <>
          <div className="oauth-preview-outcome-identity">
            <ClientLogo key={`${client.client_id}-${client.logo_uri}`} client={client} />
            {step === "allowed"
              ? <CircleCheck size={28} className="oauth-preview-outcome-state oauth-preview-positive" aria-hidden />
              : <CircleSlash size={28} className="oauth-preview-outcome-state" aria-hidden />}
          </div>
          <h1 ref={heading} tabIndex={-1}>{step === "allowed" ? "Access approved" : "Connection declined"}</h1>
          <p className="oauth-preview-lead">{step === "allowed"
            ? `Continue in ${client.client_name} to finish connecting to Vxpipe.`
            : `${client.client_name} wasn’t given new access to your Vxpipe account.`}</p>
          {step === "allowed" ? <>
            <dl className="oauth-preview-receipt">
              <div><dt>Client</dt><dd>{client.client_name}</dd></div>
              <div><dt>Access</dt><dd>{access === "empty" ? "No action permissions" : access === "all-tenants" ? "All tenants, including future tenants" : "Demo"}</dd></div>
              <div><dt>Expires</dt><dd>In 30 days</dd></div>
            </dl>
            <p className="oauth-preview-outcome-note">You’re in control. Revoke access anytime in Settings → Your connections.</p>
            <div className="oauth-preview-outcome-actions">
              <Button className="oauth-preview-allow" onClick={() => navigate("console")}>Back to Vxpipe <ArrowRight size={16} aria-hidden /></Button>
              <a className="oauth-preview-outcome-link" href="/account/connections" onClick={(event) => { event.preventDefault(); navigate("connections"); }}>Manage connected clients</a>
            </div>
          </> : <>
            <p className="oauth-preview-declined-note">Your existing connections are unchanged.</p>
            <div className="oauth-preview-outcome-actions">
              <Button className="oauth-preview-allow" onClick={() => navigate("console")}>Back to Vxpipe <ArrowRight size={16} aria-hidden /></Button>
            </div>
            <p className="oauth-preview-outcome-note">Changed your mind? Start a new connection from {client.client_name}.</p>
          </>}
        </>}
      </main>
    </div>
  );
}
