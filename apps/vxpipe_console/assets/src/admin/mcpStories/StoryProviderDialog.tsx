import { LoaderCircle } from "lucide-react";
import { useEffect, useId, useRef, useState } from "react";
import { credentialInputClass } from "../credentials/ApiKeyCredentialFields";
import { ServiceCredentialForm } from "../ServiceCredentialForm";
import { SetupDialog } from "../SetupDialog";
import { Button } from "../Button";
import { TelnyxWebhookField } from "../TelnyxWebhookField";
import { telnyxWebhookUrl } from "../setupPublicOrigin";
import {
  setupProvider,
  setupProviders,
  type SetupConnection,
  type SetupProvider,
  type SetupProviderId,
  type SetupServiceScope,
} from "../setupCatalog";
import type {
  CredentialDraft,
  CredentialTestResult,
} from "../serviceTypes";

import type { ServiceModalState } from "../ServiceSetupModal";

export function StoryProviderDialog({
  state,
  onClose,
  onSubmit,
  onTest,
  connections = [],
  providers = setupProviders,
  scope,
  publicOrigin,
  webhookUrls,
  platformConnections = [],
  onOverride,
  onUsePlatform,
  onManagePlatform,
  telephonySetup = true,
  bindingName,
  applicationId = "",
  onSaveApplication,
}: {
  state: ServiceModalState;
  onClose: () => void;
  onSubmit: (draft: CredentialDraft) => void;
  onTest?: (draft: CredentialDraft) => Promise<CredentialTestResult>;
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
  applicationId?: string;
  onSaveApplication?: (applicationId: string) => void;
}) {
  const fieldId = useId();
  const [application, setApplication] = useState(applicationId);
  const [applicationError, setApplicationError] = useState("");
  const [editingCredentials, setEditingCredentials] = useState(false);
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
  const tenantApplication = provider?.id === "telnyx" && scope.kind === "tenant" && telephonySetup;
  const applicationOnly = tenantApplication && connected && !editingCredentials;
  const pending = state.status === "submitting" || state.status === "testing";
  function saveApplication() {
    if (!tenantApplication) return true;
    if (!/^[\x21-\x7e]{1,128}$/.test(application.trim())) {
      setApplicationError("Enter the Voice API application ID without spaces.");
      contentRef.current?.querySelector<HTMLInputElement>("[data-application-id]")?.focus();
      return false;
    }
    onSaveApplication?.(application.trim());
    return true;
  }
  const applicationField = tenantApplication ? <>
    <div className="grid gap-1.5 text-sm">
      <label className="font-semibold" htmlFor={`${fieldId}-application`}>Voice API application ID</label>
      <input id={`${fieldId}-application`} data-application-id className={credentialInputClass}
        value={application} disabled={pending} maxLength={128} spellCheck={false}
        aria-describedby={`${fieldId}-application-hint`} aria-invalid={Boolean(applicationError)}
        onChange={event => { setApplication(event.target.value); setApplicationError(""); }} />
      <p id={`${fieldId}-application-hint`} className="text-xs text-[var(--admin-muted)]">
        Use a different Voice API application for each tenant. Phone numbers are set in call specs.
      </p>
    </div>
    {applicationError && <p role="alert" className="text-sm text-[var(--admin-red)]">{applicationError}</p>}
  </> : null;
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
  }, [state.provider, state.overriding, editingCredentials]);
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

    >
      <div ref={contentRef} className="mcp-dialog-scroll story-provider-credentials">
        {provider ? (
          <>
            {bindingName ? <p>Binding: {bindingName}</p> : null}
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
            {inherited || applicationOnly ? (
              <div className="setup-inherited-detail">
                {state.message ? (
                  <p className="text-sm text-[var(--admin-red)]" role="alert">
                    {state.message}
                  </p>
                ) : null}
                <p>{tenantApplication
                  ? inherited ? "Using the platform’s API key and public key. The application ID belongs to this tenant." : "Using this tenant’s saved credentials. You can update its application ID separately."
                  : "This tenant uses the platform service. Platform credentials are managed in Platform services."}</p>
                <div className="setup-scope-actions">
                  {!inherited && <Button onClick={() => setEditingCredentials(true)}>Update credentials</Button>}
                  {inherited && onOverride ? (
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
                {tenantApplication ? <form className="grid gap-4 telnyx-application-form" noValidate onSubmit={event => {
                  event.preventDefault();
                  if (saveApplication()) onClose();
                }}>
                  {applicationField}
                  {webhook}
                  <div className="setup-credential-actions">
                    <Button type="button" disabled={pending} onClick={onClose}>Cancel</Button>
                    <Button type="submit" disabled={pending}>Save</Button>
                  </div>
                </form> : webhook}
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
                onSubmit={draft => { if (saveApplication()) onSubmit(draft); }}
                onTest={onTest}
                showTelnyxPublicKey={telephonySetup}
                providerLocked
                showProvider={false}
                status={state.status === "testing" ? "idle" : state.status}
                submitLabel="Save"
                submittingLabel={
                  state.operation === "removal" ? "Updating…" : "Saving…"
                }
                beforeActions={<>
                  {applicationField}
                  {provider.id === "telnyx" && scope.kind === "platform" && <p className="text-sm text-[var(--admin-muted)]">Each tenant sets its own Voice API application ID in its Telnyx connection.</p>}
                  {webhook}
                </>}
              />
            )}
            {!inherited &&
            connected &&
            scope.kind === "tenant" &&
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
                  {provider.id === "telnyx" && webhookUrl
                    ? " Your application ID stays the same. Update its webhook URL in Telnyx after switching."
                    : ""}
                </p>
                <Button
                  disabled={state.status === "submitting"}
                  onClick={() => onUsePlatform(provider.id)}
                >
                  Use platform service
                </Button>
              </div>
            ) : null}

          </>
        ) : (
          <p className="setup-service-placeholder">
            Select a service above to enter its connection details.
          </p>
        )}
      </div>
    </SetupDialog>
  );
}
