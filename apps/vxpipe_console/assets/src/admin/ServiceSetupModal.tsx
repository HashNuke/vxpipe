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
import type {
  CredentialDraft,
  CredentialTestResult,
} from "./serviceTypes";

export type ServiceModalState = {
  provider: SetupProviderId | null;
  group?: "ai" | "telephony";
  status: "idle" | "testing" | "submitting" | "error";
  message?: string;
  overriding?: boolean;
  operation?: "credentials" | "removal";
};

export function ServiceSetupModal({
  state,
  onClose,
  onSubmit,
  onTest,
  onSelect,
  connections = [],
  providers = setupProviders,
  scope,
  publicOrigin,
  webhookUrls,
  platformConnections = [],
  onOverride,
  onUsePlatform,
  onRemove,
  onManagePlatform,
  telephonySetup = true,
  bindingName,
}: {
  state: ServiceModalState;
  onClose: () => void;
  onSubmit: (draft: CredentialDraft) => void;
  onTest?: (draft: CredentialDraft) => Promise<CredentialTestResult>;
  onSelect: (provider: SetupProviderId | null) => void;
  connections?: SetupConnection[];
  providers?: SetupProvider[];
  scope: SetupServiceScope;
  publicOrigin?: string;
  webhookUrls?: { platform: string; tenant: string | null };
  telephonySetup?: boolean;
  bindingName?: string;
  onManagePlatform?: () => void;
  platformConnections?: SetupConnection[];
  onOverride?: () => void;
  onUsePlatform?: (provider: SetupProviderId) => void;
  onRemove?: (provider: SetupProviderId) => void;
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
  const connected = Boolean(selected) && !state.overriding;
  const hasPlatform = platformConnections.some(
    (item) => item.provider === provider?.id,
  );
  const effectiveScope = inherited ? { kind: "platform" as const } : scope;
  const webhookUrl = webhookUrls
    ? effectiveScope.kind === "platform"
      ? webhookUrls.platform
      : webhookUrls.tenant
    : publicOrigin
      ? telnyxWebhookUrl(publicOrigin, effectiveScope)
      : null;
  const webhook =
    provider?.id === "telnyx" &&
    webhookUrl &&
    telephonySetup &&
    (!bindingName || bindingName === "telnyx") ? (
      <>
        <TelnyxWebhookField key={webhookUrl} url={webhookUrl} />
        {state.overriding ? (
          <p className="setup-secret-note">
            Update your Telnyx Voice API application to use this tenant webhook
            URL after saving.
          </p>
        ) : null}
      </>
    ) : null;
  useEffect(() => {
    contentRef.current
      ?.querySelector<HTMLInputElement>("input:not([disabled])")
      ?.focus();
  }, [state.provider, state.overriding]);
  return (
    <SetupDialog
      anchorTop
      busy={state.status === "submitting" || state.status === "testing"}
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
              disabled={
                state.status === "submitting" || state.status === "testing"
              }
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
            {state.status === "submitting" || state.status === "testing" ? (
              <p className="setup-validation" role="status">
                <LoaderCircle
                  aria-hidden="true"
                  className="animate-spin motion-reduce:animate-none"
                  size={16}
                />
                {state.status === "testing"
                  ? `Testing credentials with ${provider.name}…`
                  : state.operation === "removal"
                  ? "Removing service…"
                  : "Saving credentials…"}
              </p>
            ) : null}
            {inherited ? (
              <div className="setup-inherited-detail">
                {state.message ? (
                  <p className="text-sm text-[var(--admin-red)]" role="alert">
                    {state.message}
                  </p>
                ) : null}
                <p>
                  This tenant uses the platform service. Platform credentials
                  are managed in Platform services.
                </p>
                {webhook}
                <div className="setup-scope-actions">
                  {onOverride ? (
                    <Button
                      disabled={state.status === "submitting"}
                      onClick={onOverride}
                    >
                      Override for this tenant
                    </Button>
                  ) : null}
                  {inherited && onManagePlatform ? (
                    <Button
                      disabled={state.status === "submitting"}
                      onClick={onManagePlatform}
                    >
                      Manage platform services
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
                    : (selected?.savedFields ??
                      (provider.id === "twilio"
                        ? ["accountSid", "authToken"]
                        : selected?.telephonyPublicKeyConfigured
                          ? ["apiKey", "publicKey"]
                          : ["apiKey"]))
                }
                message={state.message}
                onCancel={onClose}
                onSubmit={onSubmit}
                onTest={onTest}
                showTelnyxPublicKey={telephonySetup}
                providerLocked
                showProvider={false}
                status={state.status === "testing" ? "idle" : state.status}
                submitLabel="Save"
                submittingLabel={
                  state.operation === "removal" ? "Updating…" : "Saving…"
                }
                beforeActions={webhook}
              />
            )}
            {!inherited &&
            connected &&
            (onRemove ||
              (scope.kind === "tenant" && hasPlatform && onUsePlatform)) &&
            !state.overriding ? (
              <div className="setup-scope-actions setup-restore-platform">
                {scope.kind === "tenant" && hasPlatform && onUsePlatform ? (
                  <>
                    <p>
                      Switching to the platform service removes this tenant
                      override
                      {provider.id === "telnyx"
                        ? " and changes its webhook URL"
                        : ""}
                      .
                      {provider.id === "telnyx" && webhookUrl
                        ? " Update your Telnyx Voice API application after switching."
                        : ""}
                    </p>
                    <Button
                      disabled={state.status === "submitting"}
                      onClick={() => onUsePlatform?.(provider.id)}
                    >
                      Use platform service
                    </Button>
                  </>
                ) : null}
                {onRemove &&
                !(scope.kind === "tenant" && hasPlatform && onUsePlatform) ? (
                  <Button
                    variant="ghost"
                    disabled={state.status === "submitting"}
                    onClick={() => onRemove?.(provider.id)}
                  >
                    Remove service
                  </Button>
                ) : null}
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
