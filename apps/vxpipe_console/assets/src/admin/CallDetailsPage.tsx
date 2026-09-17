import { AlertTriangle } from "lucide-react";
import { CallConsole } from "@vxpipe/react";

import { AdminShell } from "./AdminShell";
import { Breadcrumbs } from "./Breadcrumbs";
import { CallIdentity } from "./CallIdentity";
import { CallDetailsSkeleton } from "./CallDetailsSkeleton";
import type { CallDetailsPageState } from "./callDetailsTypes";
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
            href: `/admin/tenants/${encodeURIComponent(state.tenant.key)}/calls?definition_id=${encodeURIComponent(state.definition.id)}`,
            onSelect: onSelectDefinition,
          },
        ]
      : []),
    { label: "Call details" },
  ];
  const callIdentity = (
    <CallIdentity
      callId={state.callId}
      definitionRevision={state.definitionRevision}
    />
  );

  return (
    <AdminShell showHeader={false} theme={theme}>
      <main
        aria-busy={state.status === "loading" ? "true" : undefined}
        className="mx-auto w-full max-w-[1600px] px-4 py-4 sm:px-6"
      >
        <h1 className="sr-only">Call details</h1>
        <Breadcrumbs items={breadcrumbs} />
        {state.status !== "ready" ? <div className="mb-3">{callIdentity}</div> : null}
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
              headerContext={callIdentity}
              maxHeight="calc(100dvh - 76px)"
              theme={theme}
            />
          </>
        ) : null}
      </main>
    </AdminShell>
  );
}
