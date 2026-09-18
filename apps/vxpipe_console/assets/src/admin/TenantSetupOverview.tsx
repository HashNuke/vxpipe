import { ArrowRight, ArrowUpRight, Building2, Plus } from "lucide-react";
import { Button } from "./Button";
import {
  missingCapabilities,
  voiceSetupReady,
  setupProviders,
  type SetupProvider,
  capabilityLabels,
  type SetupConnection,
  type SetupTenant,
} from "./setupCatalog";

export function TenantSetupOverview({
  items,
  providers = setupProviders,
  onSetup,
  onOpen,
  onCreate,
}: {
  providers?: SetupProvider[];
  items: Array<{
    tenant: SetupTenant;
    connections: SetupConnection[];
    hasCallSpecs: boolean;
  }>;
  onSetup: (tenant: SetupTenant) => void;
  onOpen: (tenant: SetupTenant) => void;
  onCreate: () => void;
}) {
  const demo =
    items.length === 1 && items[0].tenant.demo ? items[0] : undefined;
  const demoMissing =
    demo && !voiceSetupReady(demo.connections, providers)
      ? missingCapabilities(demo.connections, providers)
      : [];
  return (
    <>
      <header className="setup-page-heading setup-directory-heading">
        <div>
          <h1>Tenants</h1>
          <p>Manage your workspaces, services and conversations.</p>
        </div>
        <Button className="setup-primary" onClick={onCreate}>
          <Plus aria-hidden="true" size={16} />
          New tenant
        </Button>
      </header>
      {demo && (demoMissing.length > 0 || !demo.hasCallSpecs) ? (
        <section aria-label="Continue demo setup" className="setup-nudge">
          <div className="setup-nudge-icon">
            <Building2 aria-hidden="true" size={24} />
          </div>
          <div>
            <h2>Make your first call with {demo.tenant.name}</h2>
            <p>
              Tenant created: {demo.tenant.name}. You can rename this tenant
              later.
            </p>
            <p>
              {demoMissing.length
                ? `Connect ${demoMissing.map((capability) => capabilityLabels[capability]).join(", ")} to try the samples.`
                : "Your services are ready. Choose a sample to get started."}
            </p>
          </div>
          <Button
            className="setup-primary"
            onClick={() => onSetup(demo.tenant)}
          >
            Continue setup
            <ArrowRight aria-hidden="true" size={16} />
          </Button>
        </section>
      ) : null}
      <div className="setup-tenant-list">
        <div className="setup-tenant-labels">
          <span>Tenant</span>
          <span>Setup</span>
          <span className="sr-only">Actions</span>
        </div>
        {items.map(({ tenant, connections, hasCallSpecs }) => {
          const missing = voiceSetupReady(connections, providers)
            ? []
            : missingCapabilities(connections, providers);
          return (
            <div className="setup-tenant-row" key={tenant.key}>
              <button
                className="setup-tenant-name"
                onClick={() => onOpen(tenant)}
              >
                <strong>{tenant.name}</strong>
                <ArrowUpRight aria-hidden="true" size={15} />
              </button>
              <span>
                {missing.length === 3
                  ? "Services not connected"
                  : missing.length
                    ? `${3 - missing.length} of 3 capabilities · ${missing.map((capability) => capabilityLabels[capability]).join(", ")} needed`
                    : hasCallSpecs
                      ? "Services and call specs ready"
                      : "Services ready · choose a sample"}
              </span>
              <Button
                aria-label={`Set up ${tenant.name}`}
                onClick={() => onSetup(tenant)}
                variant="ghost"
              >
                {missing.length
                  ? "Set up services"
                  : hasCallSpecs
                    ? "View setup"
                    : "Continue setup"}
                <ArrowRight aria-hidden="true" size={14} />
              </Button>
            </div>
          );
        })}
      </div>
    </>
  );
}
