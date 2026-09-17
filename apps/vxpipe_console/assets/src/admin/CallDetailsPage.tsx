import { CallConsole } from "@vxpipe/react";
import { AlertTriangle } from "lucide-react";

import { AdminShell } from "./AdminShell";
import { Breadcrumbs } from "./Breadcrumbs";
import { CallDetailsBackLink } from "./CallDetailsBackLink";
import { CallDetailsConsoleHeader } from "./CallDetailsConsoleHeader";
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
  const callsBreadcrumb = [...breadcrumbs].reverse().find((item) => item.href);
  const callContext = (
    <div className="flex min-w-0 items-center gap-3">
      {callsBreadcrumb ? <CallDetailsBackLink item={callsBreadcrumb} /> : null}
      {callIdentity}
      {state.status === "ready" && state.completeness === "incomplete" ? (
        <span
          className="inline-flex shrink-0 items-center gap-1 text-[var(--admin-amber)]"
          role="status"
          title="This call history may be incomplete."
        >
          <AlertTriangle aria-hidden="true" className="size-3" />
          Partial history
        </span>
      ) : null}
    </div>
  );

  if (state.status === "ready") {
    return (
      <AdminShell showHeader={false} theme={theme}>
        <main className="h-dvh w-full overflow-hidden">
          <h1 className="sr-only">Call details</h1>
          <CallConsole
            controller={state.controller}
            header={
              <CallDetailsConsoleHeader
                breadcrumbs={breadcrumbs}
              />
            }
            headerVisibility="desktop"
            headerContext={callContext}
            layout="fill"
            theme={theme}
          />
        </main>
      </AdminShell>
    );
  }

  return (
    <AdminShell showHeader={false} theme={theme}>
      <main
        aria-busy={state.status === "loading" ? "true" : undefined}
        className="mx-auto w-full max-w-[1600px] px-4 py-4 sm:px-6"
      >
        <h1 className="sr-only">Call details</h1>
        <Breadcrumbs items={breadcrumbs} />
        <div className="mb-3">{callIdentity}</div>
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
      </main>
    </AdminShell>
  );
}
