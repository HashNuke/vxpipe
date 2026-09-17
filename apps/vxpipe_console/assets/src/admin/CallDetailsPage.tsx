import { AlertTriangle } from "lucide-react";
import { CallConsole } from "@vxpipe/react";

import { AdminShell } from "./AdminShell";
import { Breadcrumbs } from "./Breadcrumbs";
import { CallDetailsSkeleton } from "./CallDetailsSkeleton";
import type { CallDetailsPageState } from "./callDetailsTypes";
import { PageHeader } from "./PageHeader";
import { PageNotice } from "./PageNotice";

export function CallDetailsPage({
  state,
  theme = "dark",
  onSelectDefinition,
  onSelectTenant,
  onSelectTenants,
}: {
  state: CallDetailsPageState;
  theme?: "dark" | "light";
  onSelectDefinition?: () => void;
  onSelectTenant?: () => void;
  onSelectTenants?: () => void;
}) {
  const definitionLabel = state.definition
    ? state.definition.name ?? state.definition.id
    : null;
  const breadcrumbs = [
    { label: "Tenants", href: "/admin", onSelect: onSelectTenants },
    {
      label: state.tenant.name ?? state.tenant.key,
      href: `/admin/tenants/${encodeURIComponent(state.tenant.key)}`,
      onSelect: onSelectTenant,
    },
    ...(state.definition && definitionLabel
      ? [
          {
            label: definitionLabel,
            href: `/admin/tenants/${encodeURIComponent(state.tenant.key)}/definitions/${encodeURIComponent(state.definition.id)}`,
            onSelect: onSelectDefinition,
          },
        ]
      : []),
    { label: "Call details" },
  ];

  return (
    <AdminShell theme={theme}>
      <main
        aria-busy={state.status === "loading" ? "true" : undefined}
        className="mx-auto w-full max-w-[1600px] px-4 py-6 sm:px-6 sm:py-8"
      >
        <Breadcrumbs items={breadcrumbs} />
        <PageHeader
          description={
            definitionLabel && state.definitionRevision !== null
              ? `${definitionLabel} · definition revision r${state.definitionRevision}`
              : "Inspect the latest available state for this call."
          }
          title="Call details"
        />
        <div className="mb-4 flex min-w-0 items-center gap-2 text-sm text-[var(--admin-muted)]">
          <span>Call</span>
          <code className="truncate font-mono text-xs text-[var(--admin-ink)]" title={state.callId}>
            {state.callId}
          </code>
        </div>

        {state.status === "loading" ? <CallDetailsSkeleton /> : null}
        {state.status === "unavailable" ? (
          <PageNotice kind="unavailable" message={state.message} title="Call unavailable" />
        ) : null}
        {state.status === "malformed" ? (
          <PageNotice
            kind="unavailable"
            message={state.message}
            title="Call data could not be read"
          />
        ) : null}
        {state.status === "ready" ? (
          <>
            {state.completeness === "incomplete" ? (
              <div
                className="mb-3 flex items-center gap-2 border border-[var(--admin-amber)]/35 bg-[var(--admin-amber-soft)] px-3 py-2 text-sm text-[var(--admin-amber)]"
                role="status"
              >
                <AlertTriangle aria-hidden="true" className="size-4 shrink-0" />
                <span>
                  <strong>Partial call history.</strong> This call history may be incomplete.
                </span>
              </div>
            ) : null}
            <CallConsole
              controller={state.controller}
              maxHeight="min(760px, calc(100dvh - 220px))"
              theme={theme}
            />
          </>
        ) : null}
      </main>
    </AdminShell>
  );
}
