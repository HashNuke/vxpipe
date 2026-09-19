import { LoaderCircle, ShieldCheck } from "lucide-react";
import { useEffect, useRef } from "react";
import { ServiceCredentialForm } from "./ServiceCredentialForm";
import { SetupDialog } from "./SetupDialog";
import { Button } from "./Button";
import { TelnyxWebhookField } from "./TelnyxWebhookField";
import { telnyxWebhookUrl } from "./setupPublicOrigin";
import {
  capabilityLabels,
  providerInGroup,
  setupProvider,
  setupProviders,
  type SetupConnection,
  type SetupProvider,
  type SetupProviderId,
  type SetupServiceScope,
} from "./setupCatalog";
import type { CredentialDraft } from "./serviceTypes";

export type ServiceModalState = {
  provider: SetupProviderId | null;
  group?: "ai" | "telephony";
  status: "idle" | "submitting" | "error";
  message?: string;
  overriding?: boolean;
};

export function ServiceSetupModal({
  state,
  onClose,
  onSubmit,
  onSelect,
  connections = [],
  providers = setupProviders,
  scope,
  publicOrigin,
  platformConnections = [],
  onOverride,
  onUsePlatform,
  onDisable,
  onManagePlatform,
  telephonySetup = true,
  bindingName,
}: {
  state: ServiceModalState;
  onClose: () => void;
  onSubmit: (draft: CredentialDraft) => void;
  onSelect: (provider: SetupProviderId | null) => void;
  connections?: SetupConnection[];
  providers?: SetupProvider[];
  scope: SetupServiceScope;
  publicOrigin?: string;
  telephonySetup?: boolean;
  bindingName?: string;
  onManagePlatform?: () => void;
  platformConnections?: SetupConnection[];
  onOverride?: () => void;
  onUsePlatform?: (provider: SetupProviderId) => void;
  onDisable?: (provider: SetupProviderId) => void;
}) {
  const contentRef = useRef<HTMLDivElement>(null);
  const provider = state.provider
    ? setupProvider(state.provider, providers)
    : undefined;
  const selected = connections.find((item) => item.provider === provider?.id);
  const inherited =
    scope.kind === "tenant" &&
    selected?.source === "platform" &&
    !state.overriding;
  const disabled = selected?.status === "disabled" && !state.overriding;
  const connected = Boolean(selected) && !state.overriding;
  const hasPlatform = platformConnections.some(
    (item) => item.provider === provider?.id,
  );
  const effectiveScope = inherited ? { kind: "platform" as const } : scope;
  const webhook =
    provider?.id === "telnyx" && publicOrigin && telephonySetup ? (
      <TelnyxWebhookField
        key={telnyxWebhookUrl(publicOrigin, effectiveScope)}
        url={telnyxWebhookUrl(publicOrigin, effectiveScope)}
      />
    ) : null;
  useEffect(() => {
    contentRef.current
      ?.querySelector<HTMLInputElement>("input:not([disabled])")
      ?.focus();
  }, [state.provider, state.overriding]);
  return (
    <SetupDialog
      anchorTop
      busy={state.status === "submitting"}
      onClose={onClose}
      title={
        provider
          ? `${state.overriding ? "Override" : connected ? "Manage" : "Connect"} ${provider.name}`
          : "Connect a service"
      }
      headerContent={
        <div className="setup-service-header">
          <div className="setup-service-heading">
            <select
              aria-label="Service"
              disabled={state.status === "submitting"}
              value={state.provider ?? ""}
              onChange={(event) =>
                onSelect(
                  event.target.value
                    ? (event.target.value as SetupProviderId)
                    : null,
                )
              }
            >
              <option value="">Select a service</option>
              {providers
                .filter(
                  (item) => !state.group || providerInGroup(item, state.group),
                )
                .map((item) => (
                  <option key={item.id} value={item.id}>
                    {item.name}
                  </option>
                ))}
            </select>
          </div>
        </div>
      }
    >
      <div ref={contentRef}>
        {provider ? (
          <>
            {bindingName ? <p>Binding: {bindingName}</p> : null}
            <div className="setup-tags setup-modal-capabilities">
              {provider.capabilities.map((capability) => (
                <span key={capability}>{capabilityLabels[capability]}</span>
              ))}
            </div>
            {state.status === "submitting" ? (
              <p className="setup-validation" role="status">
                <LoaderCircle
                  aria-hidden="true"
                  className="animate-spin motion-reduce:animate-none"
                  size={16}
                />
                Validating credentials with {provider.name}…
              </p>
            ) : null}
            {inherited || disabled ? (
              <div className="setup-inherited-detail">
                <p>
                  {disabled
                    ? "This service is disabled for this tenant."
                    : "This tenant uses the platform service. Platform credentials are managed in Platform services."}
                </p>
                {inherited ? webhook : null}
                <div className="setup-scope-actions">
                  {disabled && hasPlatform && onUsePlatform ? (
                    <Button onClick={() => onUsePlatform?.(provider.id)}>
                      Use platform service
                    </Button>
                  ) : null}
                  {onOverride ? (
                    <Button onClick={onOverride}>
                      {disabled
                        ? "Connect for this tenant"
                        : "Override for this tenant"}
                    </Button>
                  ) : null}
                  {inherited && onManagePlatform ? (
                    <Button onClick={onManagePlatform}>
                      Manage platform services
                    </Button>
                  ) : null}
                  {inherited && onDisable ? (
                    <Button
                      variant="ghost"
                      onClick={() => onDisable?.(provider.id)}
                    >
                      Disable for this tenant
                    </Button>
                  ) : null}
                </div>
              </div>
            ) : (
              <ServiceCredentialForm
                key={provider.id}
                initialProvider={provider.id}
                savedFields={
                  !connected
                    ? []
                    : provider.id === "twilio"
                      ? ["accountSid", "authToken"]
                      : selected?.telephonyPublicKeyConfigured
                        ? ["apiKey", "publicKey"]
                        : ["apiKey"]
                }
                message={state.message}
                onCancel={onClose}
                onSubmit={onSubmit}
                showTelnyxPublicKey={telephonySetup}
                providerLocked
                showProvider={false}
                status={state.status}
                submitLabel="Validate and save"
                submittingLabel="Validating…"
                beforeActions={webhook}
              />
            )}
            {scope.kind === "tenant" &&
            !inherited &&
            !disabled &&
            hasPlatform &&
            onUsePlatform &&
            !state.overriding ? (
              <div className="setup-scope-actions setup-restore-platform">
                <p>
                  Switching to the platform service removes this tenant override
                  {provider.id === "telnyx"
                    ? " and changes its webhook URL"
                    : ""}
                  .
                </p>
                <Button
                  disabled={state.status === "submitting"}
                  onClick={() => onUsePlatform?.(provider.id)}
                >
                  Use platform service
                </Button>
                <Button
                  variant="ghost"
                  disabled={state.status === "submitting"}
                  onClick={() => onDisable?.(provider.id)}
                >
                  Disable for this tenant
                </Button>
              </div>
            ) : null}
            {scope.kind === "tenant" && !inherited ? (
              <p className="setup-secret-note">
                <ShieldCheck aria-hidden="true" size={16} />
                Credentials belong to the tenant. Saved secrets are never shown.
              </p>
            ) : null}
          </>
        ) : null}
      </div>
    </SetupDialog>
  );
}
