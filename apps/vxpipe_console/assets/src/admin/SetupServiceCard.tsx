import { CheckCheck, Pencil, TriangleAlert } from "lucide-react";
import { Button } from "./Button";
import { ServiceLogo } from "./ServiceLogo";
import {
  capabilityLabels,
  type SetupConnection,
  type SetupProvider,
} from "./setupCatalog";

export function SetupServiceCard({
  provider,
  connection,
  onSelect,
  platform = false,
  overridesPlatform = false,
}: {
  provider: SetupProvider;
  connection?: SetupConnection;
  onSelect: () => void;
  platform?: boolean;
  overridesPlatform?: boolean;
}) {
  const connected = connection?.status === "connected";
  const needsPublicKey =
    provider.id === "telnyx" && !connection?.telephonyPublicKeyConfigured;
  const source = platform
    ? null
    : connection?.source === "platform"
      ? "Inherited from platform"
      : overridesPlatform
        ? "Tenant override"
        : null;
  return (
    <article
      aria-label={provider.name}
      className="setup-service-card setup-saved-service"
    >
      <div className="setup-service-card-heading">
        <ServiceLogo name={provider.name} provider={provider.id} />
        <h3>{provider.name}</h3>
        <div className="setup-service-card-actions">
          {connected ? (
            <span className="setup-service-status" title="Connected">
              <CheckCheck aria-hidden="true" size={18} />
              <span className="sr-only">Connected</span>
            </span>
          ) : null}
          <Button
            aria-label={`${connection ? "Manage" : "Connect"} ${provider.name}`}
            className="setup-service-edit"
            onClick={onSelect}
            title={`${connection ? "Manage" : "Connect"} ${provider.name}`}
            variant="ghost"
          >
            <Pencil aria-hidden="true" size={16} />
          </Button>
        </div>
      </div>
      {source ? <p className="setup-service-source">{source}</p> : null}
      {connection?.status === "invalid" ? (
        <p className="setup-error">Credentials need attention</p>
      ) : null}
      {connection?.status === "unavailable" ? (
        <p className="setup-error">Validation unavailable · retry</p>
      ) : null}
      <div className="setup-service-card-footer">
        <div className="setup-tags">
          {provider.capabilities.length === 0 ? <span>Credentials only</span> : null}
          {provider.capabilities.map((capability) => (
            <span key={capability}>
              {capabilityLabels[capability]}
              {capability === "telephony" && connected && needsPublicKey ? (
                <span
                  className="setup-capability-warning"
                  title="Public key needed"
                >
                  <TriangleAlert aria-hidden="true" size={13} />
                  <span className="sr-only">Public key needed</span>
                </span>
              ) : null}
            </span>
          ))}
        </div>
      </div>
    </article>
  );
}
