import { Plus, X } from "lucide-react";
import { useEffect, useRef, useState, type KeyboardEvent, type ReactNode } from "react";

import { AdminShell } from "./AdminShell";
import { Breadcrumbs } from "./Breadcrumbs";
import { Button } from "./Button";
import { PageNotice } from "./PageNotice";
import { ServiceCredentialForm } from "./ServiceCredentialForm";
import { ServiceInventory } from "./ServiceInventory";
import type { CredentialDraft, TenantServicesPageState } from "./serviceTypes";
import {
  TenantWorkspaceNavigation,
  type TenantDestination,
} from "./TenantWorkspaceNavigation";

export function TenantServicesPage({
  state,
  theme = "dark",
  onSelectTenants,
  onSelectTenant,
  onSelectWorkspace,
  onCreateCredential,
  onDismissCredential,
  headerActions,
  workspaceDestinations,
}: {
  state: TenantServicesPageState;
  theme?: "dark" | "light";
  onSelectTenants?: () => void;
  onSelectTenant?: () => void;
  onSelectWorkspace?: (destination: TenantDestination) => void;
  onCreateCredential?: (draft: CredentialDraft) => void;
  onDismissCredential?: () => void;
  headerActions?: ReactNode;
  workspaceDestinations?: TenantDestination[];
}) {
  const [open, setOpen] = useState(state.setup.open);
  const [freshAttempt, setFreshAttempt] = useState(false);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const dialogRef = useRef<HTMLDivElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);

  useEffect(() => setOpen(state.setup.open), [state.setup.open]);
  useEffect(() => {
    if (open) dialogRef.current?.querySelector<HTMLElement>("select")?.focus();
  }, [open]);
  useEffect(() => {
    if (state.setup.status !== "success") return;
    if (contentRef.current) contentRef.current.inert = false;
    setOpen(false);
    setFreshAttempt(true);
    triggerRef.current?.focus();
  }, [state.setup.resultVersion, state.setup.status]);

  function closeSetup() {
    if (contentRef.current) contentRef.current.inert = false;
    setOpen(false);
    setFreshAttempt(true);
    onDismissCredential?.();
    triggerRef.current?.focus();
  }

  function handleDialogKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key === "Escape") {
      closeSetup();
      return;
    }
    if (event.key !== "Tab" || !dialogRef.current) return;

    const focusable = Array.from(
      dialogRef.current.querySelectorAll<HTMLElement>(
        "button:not([disabled]), select:not([disabled]), input:not([disabled])",
      ),
    );
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (!first || !last) return;
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  return (
    <AdminShell headerActions={headerActions} theme={theme}>
      <main aria-busy={state.status === "loading" ? "true" : undefined} className="mx-auto w-full max-w-[1600px] px-4 py-6 sm:px-6 sm:py-8">
        <div aria-hidden={open ? "true" : undefined} inert={open ? true : undefined} ref={contentRef}>
        <Breadcrumbs items={[{ label: "Tenants", href: "/admin", onSelect: onSelectTenants }, { label: state.tenant.name, href: `/admin/tenants/${encodeURIComponent(state.tenant.key)}`, onSelect: onSelectTenant }, { label: "Services" }]} />
        <TenantWorkspaceNavigation
          active="services"
          destinations={workspaceDestinations}
          onSelect={onSelectWorkspace}
          tenant={state.tenant}
        />
        <header className="mb-6 flex items-center justify-between gap-4 border-b border-[var(--admin-line)] pb-5 sm:mb-8">
          <h1 className="text-xl font-bold tracking-[-0.02em]">Services</h1>
          <Button disabled={state.status !== "ready"} onClick={() => { setFreshAttempt(true); setOpen(true); }} ref={triggerRef} type="button"><Plus aria-hidden="true" className="size-4" />Add credential</Button>
        </header>
        {state.status === "ready" && state.truncated ? (
          <p className="mb-4 text-sm text-[var(--admin-muted)]" role="status">
            Showing a partial inventory. More services are configured for this tenant.
          </p>
        ) : null}
        <section aria-label="Service inventory" className="overflow-hidden rounded-sm border border-[var(--admin-line)] bg-[var(--admin-panel)]">
          {state.status === "loading" ? <div className="min-h-56 animate-pulse bg-[var(--admin-soft)] motion-reduce:animate-none" /> : null}
          {state.status === "unavailable" ? <PageNotice kind="unavailable" message={state.message} title="Services unavailable" /> : null}
          {state.status === "ready" && state.services.length === 0 ? <PageNotice kind="empty" message="Configured provider services will appear here." title="No services yet" /> : null}
          {state.status === "ready" && state.services.length > 0 ? <ServiceInventory services={state.services} /> : null}
        </section>
        {state.setup.status === "success" && !open ? <p className="mt-4 text-sm text-[var(--admin-green)]" role="status">Credential stored.</p> : null}
        </div>
        {open ? (
          <div aria-labelledby="credential-dialog-title" aria-modal="true" className="fixed inset-0 z-50 grid place-items-end bg-black/55 p-0 sm:place-items-center sm:p-6" onKeyDown={handleDialogKeyDown} ref={dialogRef} role="dialog">
            <section className="max-h-[100dvh] w-full overflow-y-auto border border-[var(--admin-line)] bg-[var(--admin-panel)] p-5 shadow-2xl sm:max-w-lg sm:rounded-sm">
              <header className="mb-5 flex items-center justify-between gap-4">
                <h2 className="text-lg font-bold" id="credential-dialog-title">Add credential</h2>
                <Button aria-label="Close credential setup" onClick={closeSetup} type="button" variant="ghost"><X aria-hidden="true" className="size-4" /></Button>
              </header>
              <ServiceCredentialForm message={freshAttempt ? undefined : state.setup.message} onCancel={closeSetup} onSubmit={(draft) => { setFreshAttempt(false); onCreateCredential?.(draft); }} status={freshAttempt ? "idle" : state.setup.status} />
            </section>
          </div>
        ) : null}
      </main>
    </AdminShell>
  );
}
