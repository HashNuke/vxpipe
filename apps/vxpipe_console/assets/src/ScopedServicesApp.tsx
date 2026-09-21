import { useEffect, useRef, useState, type ReactNode } from "react";
import { AdminShell } from "./admin/AdminShell";
import { Button } from "./admin/Button";
import {
  ServiceSetupModal,
  type ServiceModalState,
} from "./admin/ServiceSetupModal";
import { TenantSetupPage } from "./admin/TenantSetupPage";
import { TenantTelephonyApplications } from "./admin/TenantTelephonyApplications";
import {
  parseBindingDirectory,
  type BindingDirectory,
} from "./admin/serviceBindingsApi";
import {
  installedSetupProviders,
  voiceSetupReady,
  type SetupServiceScope,
} from "./admin/setupCatalog";
import {
  credentialRequest,
  testCredentialRequest,
} from "./admin/credentialApi";
import type {
  CredentialDraft,
  CredentialTestResult,
} from "./admin/serviceTypes";

type Fetch = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Promise<Response>;
type Modal = ServiceModalState & { bindingName?: string };
const defaultFetch: Fetch = (input, init) => window.fetch(input, init);
const sessionExpired = () => window.location.assign("/auth/login");

export function ScopedServicesApp({
  scope,
  csrfToken,
  fetchImpl = defaultFetch,
  onSessionExpired = sessionExpired,
  onNavigate,
  headerActions,
}: {
  scope: SetupServiceScope;
  csrfToken: string;
  fetchImpl?: Fetch;
  onSessionExpired?: () => void;
  onNavigate: (path: string) => void;
  headerActions?: ReactNode;
}) {
  const [directory, setDirectory] = useState<BindingDirectory | null>(null);
  const [phase, setPhase] = useState<"loading" | "ready" | "unavailable">(
    "loading",
  );
  const [modal, setModal] = useState<Modal | null>(null);
  const [retry, setRetry] = useState(0);
  const [notice, setNotice] = useState("");
  const saving = useRef<AbortController | null>(null);
  const trigger = useRef<HTMLElement | null>(null);
  const tenantKey = scope.kind === "tenant" ? scope.tenantKey : null;
  const prefix =
    tenantKey === null
      ? "/admin/api/platform"
      : `/admin/api/tenants/${encodeURIComponent(tenantKey)}`;
  const directoryUrl = `${prefix}/${tenantKey === null ? "services" : "service-bindings"}`;

  useEffect(() => {
    const controller = new AbortController();
    setPhase("loading");
    setDirectory(null);
    fetchImpl(directoryUrl, {
      credentials: "same-origin",
      headers: { accept: "application/json" },
      signal: controller.signal,
    })
      .then(async (response) => {
        if (controller.signal.aborted) return;
        if (response.status === 401) onSessionExpired();
        if (!response.ok) throw new Error("unavailable");
        const next = parseBindingDirectory(
          await response.json(),
          tenantKey === null
            ? { kind: "platform" }
            : { kind: "tenant", tenantKey, tenantName: "" },
        );
        if (!controller.signal.aborted) {
          setDirectory(next);
          setPhase("ready");
        }
      })
      .catch(() => {
        if (!controller.signal.aborted) setPhase("unavailable");
      });
    return () => {
      controller.abort();
      saving.current?.abort();
    };
  }, [directoryUrl, tenantKey, fetchImpl, onSessionExpired, retry]);

  function open(next: Modal) {
    trigger.current = document.activeElement as HTMLElement;
    setModal(next);
    setNotice("");
  }
  function close() {
    if (saving.current) return;
    setModal(null);
    requestAnimationFrame(() => trigger.current?.focus());
  }

  async function save(draft: CredentialDraft) {
    if (!modal || saving.current || !directory) return;
    const name = modal.bindingName ?? draft.provider;
    const existing = directory.bindings.find(
      (binding) => binding.provider === draft.provider && binding.name === name,
    );
    if (tenantKey && existing?.source === "platform" && !modal.overriding)
      return;
    const credentialId = tenantKey
      ? existing?.source === "tenant"
        ? existing.credentialId
        : null
      : existing?.credentialId;
    await mutate(
      `${prefix}/credentials${credentialId ? `/${encodeURIComponent(credentialId)}` : ""}`,
      credentialId ? "PATCH" : "POST",
      credentialRequest(draft, name),
      "credentials",
    );
  }

  async function testCredentials(
    draft: CredentialDraft,
  ): Promise<CredentialTestResult> {
    if (!modal || saving.current || !directory) {
      return {
        status: "error",
        message: "Credentials could not be tested. Try again.",
      };
    }

    const controller = new AbortController();
    const name = modal.bindingName ?? draft.provider;
    saving.current = controller;
    setModal({ ...modal, status: "testing", message: undefined });

    try {
      return await testCredentialRequest(
        `${prefix}/credentials/test`,
        draft,
        name,
        csrfToken,
        fetchImpl,
        onSessionExpired,
        controller.signal,
      );
    } finally {
      if (saving.current === controller) {
        saving.current = null;
        setModal((current) =>
          current?.status === "testing"
            ? { ...current, status: "idle" }
            : current,
        );
      }
    }
  }

  async function removeCredential() {
    if (!modal?.provider || saving.current || !directory) return;
    const name = modal.bindingName ?? modal.provider;
    const selected = directory.bindings.find(
      (binding) => binding.provider === modal.provider && binding.name === name,
    );
    if (!selected?.credentialId || (tenantKey && selected.source !== "tenant"))
      return;
    await mutate(
      `${prefix}/credentials/${encodeURIComponent(selected.credentialId)}`,
      "DELETE",
      undefined,
      "removal",
    );
  }

  async function mutate(
    url: string,
    method: string,
    body: object | undefined,
    operation: "credentials" | "removal",
  ) {
    if (!modal || saving.current) return;
    const controller = new AbortController();
    saving.current = controller;
    setModal({ ...modal, status: "submitting", operation, message: undefined });
    let stored = false;
    try {
      const response = await fetchImpl(url, {
        method,
        credentials: "same-origin",
        signal: controller.signal,
        headers: {
          "content-type": "application/json",
          accept: "application/json",
          "x-csrf-token": csrfToken,
        },
        body: JSON.stringify(body),
      });
      if (controller.signal.aborted) return;
      if (response.status === 401) {
        onSessionExpired();
        throw new Error("Your session expired. Sign in again.");
      }
      if (!response.ok)
        throw new Error(
          operation === "removal"
            ? response.status === 409
              ? "This credential is used by a telephony service. Remove that service before removing its credentials."
              : "Service could not be removed. Check the connection and try again."
            : response.status === 409
              ? "This binding already exists. Close this form and reload to edit it."
              : response.status === 422
                ? "The credentials were rejected. Check them and try again."
                : "Credentials could not be saved. Check the connection and try again.",
        );
      stored = true;
      const reloaded = await fetchImpl(directoryUrl, {
        credentials: "same-origin",
        headers: { accept: "application/json" },
        signal: controller.signal,
      });
      if (controller.signal.aborted) return;
      if (reloaded.status === 401) onSessionExpired();
      if (!reloaded.ok) throw new Error("reload unavailable");
      const next = parseBindingDirectory(await reloaded.json(), scope);
      if (controller.signal.aborted) return;
      setDirectory(next);
      setModal(null);
      setNotice(
        operation === "removal" ? "Service removed." : "Service saved.",
      );
      requestAnimationFrame(() => trigger.current?.focus());
    } catch (error) {
      if (controller.signal.aborted) return;
      if (stored) {
        setModal(null);
        setPhase("unavailable");
        setNotice(
          operation === "removal"
            ? "Service removed. Retry to load the current state."
            : "Service saved. Retry to load its current state.",
        );
      } else
        setModal({
          ...modal,
          status: "error",
          message:
            error instanceof Error
              ? error.message
              : "Credentials could not be saved. Try again.",
        });
    } finally {
      if (saving.current === controller) saving.current = null;
    }
  }

  const tenant = directory?.tenant ?? {
    key: tenantKey ?? "",
    name: scope.kind === "tenant" ? scope.tenantName : "Platform",
  };
  const bindings = directory?.bindings ?? [];
  const primary = bindings.filter(
    (binding) => binding.name === binding.provider,
  );
  const providers = directory
    ? installedSetupProviders(directory.providerCapabilities)
    : [];
  const named = bindings.filter((binding) => binding.name !== binding.provider);
  const selected = modal?.provider
    ? bindings.find(
        (binding) =>
          binding.provider === modal.provider &&
          binding.name === (modal.bindingName ?? modal.provider),
      )
    : undefined;
  const platformConnections = bindings.filter(
    (binding) => binding.platformAvailable,
  );
  return (
    <AdminShell
      breadcrumbs={
        tenantKey === null
          ? [{ label: "Platform" }, { label: "Services" }]
          : [
              {
                label: "Tenants",
                href: "/admin",
                onSelect: () => onNavigate("/admin"),
              },
              { label: tenant.name },
              { label: "Setup services" },
            ]
      }
      headerInert={modal !== null}
      headerActions={
        <div className="flex flex-wrap items-center gap-2">
          <Button
            variant="ghost"
            onClick={() =>
              onNavigate(
                tenantKey === null ? "/admin" : "/admin/platform/services",
              )
            }
          >
            {tenantKey === null ? "Tenants" : "Platform services"}
          </Button>
          {headerActions}
        </div>
      }
    >
      <main
        className="tenant-setup"
        inert={modal !== null ? true : undefined}
        aria-hidden={modal !== null ? true : undefined}
        aria-busy={phase === "loading"}
      >
        {phase === "loading" ? (
          <p role="status">Loading services…</p>
        ) : (
          <TenantSetupPage
            tenant={tenant}
            connections={primary}
            providers={providers}
            platform={tenantKey === null}
            platformConnections={platformConnections.filter(
              (binding) => binding.name === binding.provider,
            )}
            unavailable={phase === "unavailable"}
            onRetry={() => setRetry((value) => value + 1)}
            onConnect={(provider, group) =>
              open({ provider, group, status: "idle" })
            }
            onBrowse={(group) =>
              open({ provider: null, group, status: "idle" })
            }
          />
        )}
        {phase === "ready" && named.length > 0 ? (
          <section className="setup-service-group" aria-label="Named bindings">
            <h2>Named bindings</h2>
            <div className="flex flex-wrap gap-2">
              {named.map((binding) => (
                <Button
                  key={`${binding.provider}:${binding.name}`}
                  onClick={() =>
                    open({
                      provider: binding.provider,
                      bindingName: binding.name,
                      status: "idle",
                    })
                  }
                >
                  {
                    providers.find(
                      (provider) => provider.id === binding.provider,
                    )?.name
                  }
                  : {binding.name}
                </Button>
              ))}
            </div>
          </section>
        ) : null}
        {tenantKey !== null ? (
          <TenantTelephonyApplications
            key={tenantKey}
            tenantKey={tenantKey}
            csrfToken={csrfToken}
            binding={primary.find((binding) => binding.provider === "telnyx")}
            credentialsLoaded={phase === "ready"}
            webhookUrl={
              primary.find((binding) => binding.provider === "telnyx")
                ?.source === "tenant"
                ? directory?.webhookUrls?.tenant
                : directory?.webhookUrls?.platform
            }
            fetchImpl={fetchImpl}
            onSessionExpired={onSessionExpired}
            onConnectionDetails={() =>
              open({ provider: "telnyx", group: "telephony", status: "idle" })
            }
          />
        ) : null}
        {phase === "ready" && tenantKey !== null ? (
          <footer className="setup-footer">
            <p role="status">
              {voiceSetupReady(primary, providers)
                ? "Ready for voice samples"
                : "Connect supported speech and language services to run voice samples."}
            </p>
            <Button
              onClick={() =>
                onNavigate(
                  `/admin/tenants/${encodeURIComponent(tenantKey)}/call-specs`,
                )
              }
            >
              View call specs
            </Button>
            <Button
              variant="ghost"
              onClick={() =>
                onNavigate(
                  `/admin/tenants/${encodeURIComponent(tenantKey)}/services`,
                )
              }
            >
              Service inventory
            </Button>
          </footer>
        ) : null}
        {notice ? <p role="status">{notice}</p> : null}
      </main>
      {modal ? (
        <ServiceSetupModal
          state={modal}
          scope={scope}
          providers={providers}
          connections={selected ? [selected] : []}
          platformConnections={platformConnections.filter(
            (binding) => binding.name === (modal.bindingName ?? modal.provider),
          )}
          webhookUrls={directory?.webhookUrls}
          bindingName={modal.bindingName}
          onClose={close}
          onSubmit={save}
          onTest={testCredentials}
          onSelect={(provider) => {
            if (!saving.current)
              setModal({
                ...modal,
                provider,
                overriding: false,
                operation: undefined,
                bindingName: undefined,
                status: "idle",
                message: undefined,
              });
          }}
          onManagePlatform={() => onNavigate("/admin/platform/services")}
          onOverride={
            tenantKey
              ? () => {
                  if (!saving.current)
                    setModal({
                      ...modal,
                      overriding: true,
                      status: "idle",
                      message: undefined,
                    });
                }
              : undefined
          }
          onUsePlatform={tenantKey ? removeCredential : undefined}
          onRemove={removeCredential}
        />
      ) : null}
    </AdminShell>
  );
}
