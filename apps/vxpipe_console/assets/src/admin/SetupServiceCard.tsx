import * as Popover from "@radix-ui/react-popover";
import { CheckCheck, EllipsisVertical, Pencil, Trash2, TriangleAlert } from "lucide-react";
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
  onRemoveCredentials,
  platform = false,
  overridesPlatform = false,
  busy = false,
  removing = false,
}: {
  provider: SetupProvider;
  connection?: SetupConnection;
  onSelect: () => void;
  onRemoveCredentials?: () => void;
  platform?: boolean;
  overridesPlatform?: boolean;
  busy?: boolean;
  removing?: boolean;
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
      aria-busy={removing || undefined}
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
          <div
            aria-label={`${provider.name} actions`}
            className="setup-service-card-button-group"
            role="group"
          >
            <Button
              aria-label={`${connection ? "Manage" : "Connect"} ${provider.name}`}
              className="setup-service-edit"
              disabled={busy}
              onClick={onSelect}
              title={`${connection ? "Manage" : "Connect"} ${provider.name}`}
              type="button"
              variant="ghost"
            >
              <Pencil aria-hidden="true" size={16} />
            </Button>
            {onRemoveCredentials ? (
              <Popover.Root>
                <Popover.Trigger asChild>
                  <Button
                    aria-label={`More actions for ${provider.name}`}
                    className="setup-service-more"
                    disabled={busy}
                    title={`More actions for ${provider.name}`}
                    type="button"
                    variant="ghost"
                  >
                    <EllipsisVertical aria-hidden="true" size={16} />
                  </Button>
                </Popover.Trigger>
                <Popover.Content
                  align="end"
                  aria-label={`${provider.name} options`}
                  className="setup-service-card-menu shadow-sm"
                  collisionPadding={8}
                  sideOffset={6}
                >
                  <Popover.Close asChild>
                    <button
                      className="setup-service-card-menu-item"
                      onClick={onRemoveCredentials}
                      type="button"
                    >
                      <Trash2 aria-hidden="true" size={16} />
                      Remove credentials
                    </button>
                  </Popover.Close>
                </Popover.Content>
              </Popover.Root>
            ) : null}
          </div>
        </div>
      </div>
      {source ? <p className="setup-service-source">{source}</p> : null}
      {removing ? <p role="status">Removing credentials…</p> : null}
      {connection?.status === "invalid" ? (
        <p className="setup-error">Credentials need attention</p>
      ) : null}
      {connection?.status === "unavailable" ? (
        <p className="setup-error">Validation unavailable · retry</p>
      ) : null}
      <div className="setup-service-card-footer">
        <div className="setup-tags">
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
