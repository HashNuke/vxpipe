import { LoaderCircle, ShieldCheck } from "lucide-react";
import { useEffect, useRef } from "react";
import { ServiceCredentialForm } from "./ServiceCredentialForm";
import { SetupDialog } from "./SetupDialog";
import {
  capabilityLabels,
  providerInGroup,
  setupProvider,
  setupProviders,
  type SetupConnection,
  type SetupProvider,
  type SetupProviderId,
} from "./setupCatalog";
import type { CredentialDraft } from "./serviceTypes";

export type ServiceModalState = {
  provider: SetupProviderId | null;
  group?: "ai" | "telephony";
  status: "idle" | "submitting" | "error";
  message?: string;
};

export function ServiceSetupModal({
  state,
  tenantName,
  onClose,
  onSubmit,
  onSelect,
  connections = [],
  providers = setupProviders,
}: {
  state: ServiceModalState;
  tenantName: string;
  onClose: () => void;
  onSubmit: (draft: CredentialDraft) => void;
  onSelect: (provider: SetupProviderId | null) => void;
  connections?: SetupConnection[];
  providers?: SetupProvider[];
}) {
  const contentRef = useRef<HTMLDivElement>(null);
  const provider = state.provider
    ? setupProvider(state.provider, providers)
    : undefined;
  const connected = connections.some(
    (item) => item.provider === provider?.id && item.status === "connected",
  );
  useEffect(() => {
    contentRef.current
      ?.querySelector<HTMLInputElement>("input:not([disabled])")
      ?.focus();
  }, [state.provider]);
  return (
    <SetupDialog
      busy={state.status === "submitting"}
      onClose={onClose}
      title={
        provider
          ? `${connected ? "Manage" : "Connect"} ${provider.name}`
          : "Connect a service"
      }
    >
      <div ref={contentRef}>
        <label className="setup-service-select">
          Service
          <select
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
        </label>

        {provider ? (
          <>
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
            <ServiceCredentialForm
              key={provider.id}
              initialProvider={provider.id}
              message={state.message}
              onCancel={onClose}
              onSubmit={onSubmit}
              showTelnyxPublicKey
              providerLocked
              showProvider={false}
              status={state.status}
              submitLabel="Validate and save"
              submittingLabel="Validating…"
            />
            <p className="setup-secret-note">
              <ShieldCheck aria-hidden="true" size={16} />
              Credentials belong to {tenantName}. Saved secrets are never shown.
            </p>
          </>
        ) : null}
      </div>
    </SetupDialog>
  );
}
