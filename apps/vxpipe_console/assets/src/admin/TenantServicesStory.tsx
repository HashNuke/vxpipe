import { useState } from "react";
import { applyCredentialCreation, serviceFixture, type ServiceFixtureScenario } from "./serviceFixtures";
import { ConnectedProviders } from "./mcpStories/ConnectedProviders";
import { PageNotice } from "./PageNotice";
import { PageToast } from "./PageToast";
import { ServiceConnectionsPreview } from "./mcpStories/ServiceConnectionsPreview";
import { StoryProviderDialog } from "./mcpStories/StoryProviderDialog";
import { setupProviders, type SetupTenant } from "./setupCatalog";

/** Storybook inventory adapter; production TenantServicesPage is unchanged. */
export function TenantServicesStory({ scenario, tenant, readOnly = false, canReadCredentials = true }: {
  scenario: ServiceFixtureScenario;
  theme: "dark" | "light";
  onNavigate?: (path: string) => void;
  tenant?: SetupTenant;
  readOnly?: boolean;
  canReadCredentials?: boolean;
}) {
  const [state, setState] = useState(() => {
    const fixture = serviceFixture(scenario);
    return tenant ? { ...fixture, tenant } : fixture;
  });
  const [freshAttempt, setFreshAttempt] = useState(false);
  const [dismissed, setDismissed] = useState(false);
  return <div className="tenant-setup"><ServiceConnectionsPreview
    tenant={state.tenant} readOnly={readOnly} showMcpInventory={state.status === "ready"}
    initialCategory={state.status !== "ready" ? "connected" : undefined}
    connectionLoadState={state.status === "loading" ? "loading" : state.status === "unavailable" || state.truncated ? "unavailable" : "ready"}
    onRetryConnectionStatus={() => setState(current => ({ ...serviceFixture("populated"), tenant: current.tenant }))}
    providerConnections={state.status === "ready" ? state.services.map(service => ({ provider: service.provider, status: "connected", source: "tenant" })) : []}
    initialProvider={state.setup.open && !readOnly ? "google" : undefined}
    renderInventory={({ query, onConnect }) => <>
      {state.truncated && <p className="mcp-hint">Showing a partial inventory. More integrations are configured for this tenant.</p>}
      <section aria-label="Service inventory" aria-busy={state.status === "loading"}>
        {state.status === "loading" ? <div role="status" className="min-h-56 animate-pulse bg-[var(--admin-soft)] motion-reduce:animate-none"><span className="sr-only">Loading integrations</span></div>
          : state.status === "unavailable" ? <PageNotice kind="unavailable" message={state.message} title="Integrations unavailable" />
          : <ConnectedProviders query={query} readOnly={readOnly || !canReadCredentials}
              connections={state.services.map(service => ({ provider: service.provider, status: "connected", source: "tenant" }))}
              providers={[...setupProviders, { id: "vertex_ai", name: "Google Vertex AI", description: "", capabilities: [], defaultModels: {}, recommendedModels: {}, sampleCapabilities: [] }]}
              onManage={provider => { setFreshAttempt(true); onConnect(provider); }} />}
      </section>
    </>}
    renderProviderDialog={({ providerId, editing, onClose, onConnected }) => <StoryProviderDialog
      state={{ provider: providerId, status: freshAttempt ? "idle" : state.setup.status === "submitting" ? "submitting" : state.setup.message ? "error" : "idle", message: freshAttempt ? undefined : state.setup.message }}
      providers={[...setupProviders, { id: "vertex_ai", name: "Google Vertex AI", description: "", capabilities: [], defaultModels: {}, recommendedModels: {}, sampleCapabilities: [] }]}
      connections={editing && state.status === "ready" ? state.services.map(service => ({ provider: service.provider, status: "connected", source: "tenant" })) : []}
      scope={{ kind: "tenant", tenantKey: state.tenant.key, tenantName: state.tenant.name }}
      onClose={() => { setFreshAttempt(true); onClose(); }}
      onTest={async () => ({ status: "valid" })}
      onSubmit={draft => {
        const next = editing && state.status === "ready"
          ? { ...state, services: state.services.map(service => service.provider === draft.provider ? { ...service, credentialPreview: [], updatedAt: new Date().toISOString() } : service), setup: { open: false, status: "success" as const, resultVersion: state.setup.resultVersion + 1 } }
          : applyCredentialCreation(state, draft);
        setState(next);
        setFreshAttempt(false);
        setDismissed(false);
        if (next.setup.status === "success") onConnected();
      }}
    />}
  />{state.setup.status === "success" && !dismissed && <PageToast kind="success" message="Service saved." onDismiss={() => setDismissed(true)} />}</div>;
}
