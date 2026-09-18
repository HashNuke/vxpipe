import { ArrowRight, CircleCheck, Plus } from "lucide-react";
import { Button } from "./Button";
import { SetupServiceCard } from "./SetupServiceCard";
import {
  voiceSetupReady,
  providerInGroup,
  type SetupServiceGroup,
  setupProviders,
  type SetupConnection,
  type SetupProvider,
  type SetupProviderId,
  type SetupTenant,
} from "./setupCatalog";

export function TenantSetupPage({
  tenant,
  connections,
  onConnect,
  onBrowse,
  providers = setupProviders,
  onApiKeys,
  creating = false,
  unavailable = false,
  onRetry,
  platform = false,
  platformConnections = [],
}: {
  tenant: SetupTenant;
  connections: SetupConnection[];
  onConnect: (provider: SetupProviderId, group: SetupServiceGroup) => void;
  onBrowse: (group: "ai" | "telephony") => void;
  providers?: SetupProvider[];
  onApiKeys: () => void;
  creating?: boolean;
  unavailable?: boolean;
  onRetry: () => void;
  platform?: boolean;
  platformConnections?: SetupConnection[];
}) {
  const ready = voiceSetupReady(connections, providers);
  const connected = providers.filter((provider) =>
    connections.some((item) => item.provider === provider.id),
  );
  const ai = connected.filter((provider) => providerInGroup(provider, "ai"));
  const telephony = connected.filter((provider) =>
    provider.capabilities.includes("telephony"),
  );
  const addCard = (group: "ai" | "telephony") => (
    <button
      type="button"
      className="setup-service-card setup-add-service"
      onClick={() => onBrowse(group)}
    >
      <Plus aria-hidden="true" size={20} />
      <span>Connect a service</span>
    </button>
  );
  const connectButton = (group: "ai" | "telephony", hasServices: boolean) => (
    <Button
      className={`setup-group-connect${hasServices ? "" : " setup-connect-empty"}`}
      onClick={() => onBrowse(group)}
    >
      <Plus aria-hidden="true" size={16} />
      Connect a service
    </Button>
  );
  const card = (provider: SetupProvider, group: SetupServiceGroup) => (
    <SetupServiceCard
      key={provider.id}
      provider={provider}
      connection={connections.find((item) => item.provider === provider.id)}
      platform={platform}
      overridesPlatform={
        !platform &&
        platformConnections.some((item) => item.provider === provider.id)
      }
      onSelect={() => onConnect(provider.id, group)}
    />
  );
  if (unavailable)
    return (
      <div className="setup-unavailable" role="alert">
        <h1>Setup is temporarily unavailable</h1>
        <p>
          Your saved progress is safe. Try again to load this tenant’s services.
        </p>
        <Button onClick={onRetry}>Retry setup</Button>
      </div>
    );
  if (creating)
    return (
      <div aria-busy="true" className="setup-unavailable">
        <h1>Creating {tenant.name}</h1>
        <p>Your workspace is being created. Service setup is next.</p>
        <div className="setup-skeleton animate-pulse motion-reduce:animate-none" />
      </div>
    );

  return (
    <>
      {!platform ? (
        <header className="setup-page-heading setup-services-heading">
          <div className="setup-ready-title" role="status">
            <CircleCheck aria-hidden="true" size={18} />
            <div>
              <span>Tenant created: {tenant.name}</span>
              <p>
                Connect AI and Telephony services to get started. You can rename
                this tenant later.
              </p>
            </div>
          </div>
        </header>
      ) : null}
      <section aria-labelledby="setup-services-title">
        <div className="setup-section-heading">
          <h1 id="setup-services-title">
            {platform ? "Platform services" : "Setup services"}
          </h1>
        </div>
        {platform ? (
          <p className="setup-platform-description">
            Connect services once for tenants to inherit. Each tenant can use
            its own credentials instead.
          </p>
        ) : platformConnections.length > 0 ? (
          <p className="setup-platform-description">
            Platform services are available to {tenant.name}. Override a service
            to use this tenant’s own credentials.
          </p>
        ) : null}
        <section aria-label="AI providers" className="setup-service-group">
          <div className="setup-group-heading">
            <h2>AI providers</h2>
            {connectButton("ai", ai.length > 0)}
          </div>
          <div className="setup-provider-grid">
            {ai.map((provider) => card(provider, "ai"))}
            {addCard("ai")}
          </div>
        </section>
        <section aria-label="Telephony" className="setup-telephony">
          <div className="setup-group-heading">
            <div className="setup-telephony-heading">
              <h2>Telephony</h2>
              <span>Optional · for phone calls</span>
            </div>
            {connectButton("telephony", telephony.length > 0)}
          </div>
          <div className="setup-carrier-grid">
            {telephony.map((provider) => card(provider, "telephony"))}
            {addCard("telephony")}
          </div>
          <p>
            Browser-based calling does not need telephony. Phone calls need a
            telephony service.
          </p>
        </section>
      </section>
      {!platform ? (
        <footer className="setup-footer setup-services-footer">
          <Button
            className="setup-primary"
            disabled={!ready}
            onClick={onApiKeys}
          >
            Continue
            <ArrowRight aria-hidden="true" size={16} />
          </Button>
        </footer>
      ) : null}
    </>
  );
}
