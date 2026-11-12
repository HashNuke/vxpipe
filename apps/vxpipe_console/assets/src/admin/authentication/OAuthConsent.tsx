import { useRef, useState } from "react";
import { ArrowRight, Check, ChevronRight, Clock3, Globe, Plug, ShieldCheck } from "lucide-react";
import { Button } from "../Button";
import type { Theme } from "./types";
import { permissionGroups } from "./access";
import { OAuthUnavailable } from "./OAuthUnavailable";
import "./oauthConsent.css";

export type ClientMetadata = {
  client_id: string;
  client_name: string;
  client_uri?: string | null;
  logo_uri?: string | null;
};
export type Consent = ClientMetadata & {
  user_email: string;
  resource: string;
  redirect_uri: string;
  grant_lifetime_seconds: number;
  authority: {
    grants: string[];
    all_tenant_actions: string[];
    assigned_tenants: Record<string, "read" | "read_write">;
  };
};
export type ConsentStep = "consent" | "unavailable";

const permissionDetails: Record<string, string> = {
  "calls.read": "View calls and their details.",
  "call_specs.read": "View your voice-agent configurations.",
  "call_specs.write": "Create and change voice-agent configurations.",
};

function permissionLabel(key: string) {
  const accountLabels: Record<string, string> = {
    "users.members.write": "Manage member accounts",
    "users.admins.write": "Manage Admin accounts",
    "users.superadmins.write": "Manage Superadmin accounts",
  };
  if (accountLabels[key]) return accountLabels[key];
  const [resource, action] = key.split(".");
  const group = permissionGroups.find((item) => item.resource === resource);
  return group && (action === "read" || action === "write")
    ? `${action === "read" ? "Read" : "Write"} ${group.label.toLowerCase().replace(/\bapi\b/g, "API")}` : key;
}

function httpsUrl(value?: string | null): string | undefined {
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

export function OAuthConsent({ consent: client, requestId, csrfToken, theme = "dark", step = "consent", onDecision, onNavigate }: {
  consent: Consent;
  requestId: string;
  csrfToken: string;
  theme?: Theme;
  step?: ConsentStep;
  onDecision?: (decision: "approve" | "deny") => void;
  onNavigate?: (destination: "connections" | "console") => void;
}) {
  const submitted = useRef(false);
  const [submitting, setSubmitting] = useState(false);
  const website = httpsUrl(client.client_uri);
  const clientKind = client.client_id.startsWith("https://") ? "cimd" : "dcr";
  const callback = client.redirect_uri;
  const resource = client.resource;
  const permissions = client.authority.grants.map((key) => ({ key, label: permissionLabel(key), detail: permissionDetails[key] }));
  const allTenantActions = client.authority.all_tenant_actions;
  const assignedTenants = Object.entries(client.authority.assigned_tenants).sort(([a], [b]) => a.localeCompare(b));
  const duration = `${client.grant_lifetime_seconds / 86400} days`;

  function navigate(destination: "connections" | "console") {
    if (onNavigate) onNavigate(destination);
    else window.location.assign(destination === "connections" ? "/account/connections" : "/");
  }

  if (step === "unavailable") {
    return <OAuthUnavailable theme={theme} clientName={client.client_name} onBack={onNavigate ? () => onNavigate("console") : undefined} />;
  }

  return (
    <div className="vx-admin oauth-preview" data-theme={theme}>
      <header className="oauth-preview-header">
        <span className="oauth-preview-wordmark">Vxpipe</span>
        <span>MCP connection</span>
      </header>
      <main className="oauth-preview-main">
        <div className="oauth-preview-client">
          <ClientLogo key={`${client.client_id}-${client.logo_uri}`} client={client} />
          <ArrowRight size={18} aria-hidden />
          <span className="oauth-preview-vx" aria-label="Vxpipe">Vx</span>
        </div>
        <h1>Connect {client.client_name} to Vxpipe?</h1>
        <p className="oauth-preview-lead">This app wants to use the Vxpipe API on your behalf.</p>
        {website ? <a className="oauth-preview-website" href={website} target="_blank" rel="noopener noreferrer" referrerPolicy="no-referrer">
          <Globe size={15} aria-hidden /> {website.replace("https://", "")}
        </a> : null}

        <div className="oauth-preview-account">
          <span>Signed in as</span>
          <strong>{client.user_email}</strong>
        </div>

        <section className="oauth-preview-access" aria-labelledby="oauth-access-heading">
          <h2 id="oauth-access-heading">Access you’re allowing</h2>
          {permissions.length ? <ul className="oauth-preview-permissions">
            {permissions.map((permission) => <li key={permission.key}>
              <Check size={17} aria-hidden />
              <div><h3>{permission.label}</h3>{permission.detail ? <p>{permission.detail}</p> : null}</div>
            </li>)}
          </ul> : <p className="oauth-preview-empty"><strong>No action permissions available</strong><br />Your account currently has no actions to delegate to this client.</p>}
          {permissions.length > 0 && allTenantActions.length > 0 ? <div className="oauth-preview-scope">
            <h3>All tenants, including future tenants</h3>
            {allTenantActions.map((key) => <p key={key}><strong>{permissionLabel(key)}</strong></p>)}
          </div> : null}
          {permissions.length > 0 && assignedTenants.length > 0 ? <div className="oauth-preview-scope">
            <h3>For your assigned tenants</h3>
            {assignedTenants.map(([tenant, access]) => <p key={tenant}><strong>{tenant}</strong><span>{access === "read_write" ? "Read and write" : "Read"}</span></p>)}
          </div> : null}
        </section>

        <details className="oauth-preview-details">
          <summary>Connection details <ChevronRight size={16} aria-hidden /></summary>
          <dl>
            <dt>Client ID{clientKind === "cimd" ? " · metadata document" : ""}</dt><dd>{client.client_id}</dd>
            <dt>Vxpipe API</dt><dd>{resource}</dd>
            <dt>Return address</dt><dd>{callback}</dd>
            <dt>Exact permissions</dt><dd>{permissions.length ? permissions.map((permission) => <code key={permission.key}>{permission.key}</code>) : "None"}</dd>
          </dl>
        </details>

        <div className="oauth-preview-limits">
          <p><Clock3 size={16} aria-hidden /><span>Access ends after <strong>{duration}</strong>. Changes to your role or access require a new connection.</span></p>
          <p><ShieldCheck size={16} aria-hidden /><span>Revoke access anytime in <a href="/account/connections" onClick={onNavigate ? (event) => { event.preventDefault(); navigate("connections"); } : undefined}>Settings → Your connections</a>.</span></p>
        </div>
        <p className="oauth-preview-trust">Only allow this if you started the connection and trust {client.client_name}.</p>
        <form action={`/oauth/authorize/${requestId}`} method="post" className="oauth-preview-actions" aria-busy={submitting} onSubmit={(event) => {
          if (onDecision) {
            event.preventDefault();
            const submitter = (event.nativeEvent as SubmitEvent).submitter as HTMLButtonElement;
            onDecision(submitter?.value === "approve" ? "approve" : "deny");
          } else if (submitted.current) {
            event.preventDefault();
          } else {
            submitted.current = true;
            // Keep named submit buttons successful for the native form payload.
            setSubmitting(true);
          }
        }}>
          <input type="hidden" name="_csrf_token" value={csrfToken} />
          <Button type="submit" name="decision" value="deny" aria-disabled={submitting}>Deny</Button>
          <Button type="submit" name="decision" value="approve" aria-disabled={submitting} className="oauth-preview-allow">Allow connection <ArrowRight size={16} aria-hidden /></Button>
        </form>
        {submitting ? <p role="status" className="oauth-preview-return">Saving your choice…</p> : null}
        <p className="oauth-preview-return">You’ll return to {client.client_name} after choosing.</p>
      </main>
    </div>
  );
}
