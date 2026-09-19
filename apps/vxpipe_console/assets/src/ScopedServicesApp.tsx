import { useEffect, useRef, useState, type ReactNode } from "react";
import { AdminShell } from "./admin/AdminShell";
import { Button } from "./admin/Button";
import {
  ServiceSetupModal,
  type ServiceModalState,
} from "./admin/ServiceSetupModal";
import { TenantSetupPage } from "./admin/TenantSetupPage";
import {
  parseBindingDirectory,
  type BindingDirectory,
} from "./admin/serviceBindingsApi";
import {
  setupProviders,
  voiceSetupReady,
  type SetupProvider,
  type SetupServiceScope,
} from "./admin/setupCatalog";
import catalog from "./admin/setupCatalog.json";
import type { CredentialDraft } from "./admin/serviceTypes";

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
      ? existing?.tenantCredentialId
      : existing?.credentialId;
    const values =
      "apiKey" in draft.values
        ? { api_key: draft.values.apiKey }
        : {
            account_sid: draft.values.accountSid,
            auth_token: draft.values.authToken,
          };
    await mutate(
      `${prefix}/credentials${credentialId ? `/${encodeURIComponent(credentialId)}` : ""}`,
      credentialId ? "PATCH" : "POST",
      { provider: draft.provider, name, values },
      "credentials",
    );
  }

  async function setPolicy(policy: "inherit" | "disabled") {
    if (!tenantKey || !modal?.provider || saving.current) return;
    const name = modal.bindingName ?? modal.provider;
    await mutate(
      `${prefix}/service-policies/${encodeURIComponent(modal.provider)}/${encodeURIComponent(name)}`,
      "PUT",
      { policy },
      "policy",
    );
  }

  async function mutate(
    url: string,
    method: string,
    body: object,
    operation: "credentials" | "policy",
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
          operation === "policy"
            ? "Service settings could not be saved. Check the connection and try again."
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
        operation === "policy" ? "Service settings saved." : "Service saved.",
      );
      requestAnimationFrame(() => trigger.current?.focus());
    } catch (error) {
      if (controller.signal.aborted) return;
      if (stored) {
        setModal(null);
        setPhase("unavailable");
        setNotice(
          operation === "policy"
            ? "Service settings saved. Retry to load the current state."
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
  const providers = (catalog.providers as SetupProvider[]).filter(
    (provider) =>
      setupProviders.includes(provider) ||
      bindings.some((binding) => binding.provider === provider.id),
  );
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
          telephonySetup={false}
          bindingName={modal.bindingName}
          onClose={close}
          onSubmit={save}
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
          onUsePlatform={tenantKey ? () => setPolicy("inherit") : undefined}
          onDisable={tenantKey ? () => setPolicy("disabled") : undefined}
        />
      ) : null}
    </AdminShell>
  );
}
