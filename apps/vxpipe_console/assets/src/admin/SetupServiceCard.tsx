import { Check } from "lucide-react";
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
  telephony = false,
}: {
  provider: SetupProvider;
  connection?: SetupConnection;
  onSelect: () => void;
  telephony?: boolean;
}) {
  const connected = connection?.status === "connected";
  const needsPublicKey =
    telephony &&
    provider.id === "telnyx" &&
    !connection?.telephonyPublicKeyConfigured;
  return (
    <article
      aria-label={provider.name}
      className="setup-service-card setup-saved-service"
    >
      <div className="setup-service-card-heading">
        <ServiceLogo name={provider.name} provider={provider.id} />
        <h3>{provider.name}</h3>
        {connected ? (
          <span
            className={`setup-service-status${needsPublicKey ? " setup-service-status--pending" : ""}`}
          >
            {needsPublicKey ? (
              "Public key needed"
            ) : (
              <>
                <Check aria-hidden="true" size={14} />
                Connected
              </>
            )}
          </span>
        ) : null}
      </div>
      {connection?.status === "invalid" ? (
        <p className="setup-error">Credentials need attention</p>
      ) : null}
      {connection?.status === "unavailable" ? (
        <p className="setup-error">Validation unavailable · retry</p>
      ) : null}
      <div className="setup-service-card-footer">
        <div className="setup-tags">
          {provider.capabilities.map((capability) => (
            <span key={capability}>{capabilityLabels[capability]}</span>
          ))}
        </div>
        <Button
          aria-label={`${connected ? "Manage" : "Connect"} ${provider.name}`}
          onClick={onSelect}
        >
          {connected ? "Manage" : "Connect"}
        </Button>
      </div>
    </article>
  );
}
