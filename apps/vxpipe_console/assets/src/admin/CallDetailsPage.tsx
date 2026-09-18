import { CallConsole } from "@vxpipe/react";
import { AlertTriangle } from "lucide-react";

import { AdminShell } from "./AdminShell";
import { CallDetailsConsoleHeader } from "./CallDetailsConsoleHeader";
import { CallIdentity } from "./CallIdentity";
import { CallDetailsSkeleton } from "./CallDetailsSkeleton";
import type { CallDetailsPageState } from "./callDetailsTypes";
import { PageNotice } from "./PageNotice";

export function CallDetailsPage({
  state,
  theme = "dark",
  contextHref = (path) => path,
}: {
  state: CallDetailsPageState;
  theme?: "dark" | "light";
  contextHref?: (path: string) => string;
}) {
  const callSpecLabel = state.callSpec
    ? state.callSpec.name ?? state.callSpec.id
    : null;
  const header = (
    <CallDetailsConsoleHeader
      breadcrumbs={[
        { label: "Tenants", href: contextHref("/admin") },
        {
          label: state.tenant.name ?? state.tenant.key,
          href: contextHref(`/admin/tenants/${encodeURIComponent(state.tenant.key)}/call-specs`),
        },
        ...(state.callSpec && callSpecLabel
          ? [{
              label: callSpecLabel,
              href: contextHref(`/admin/tenants/${encodeURIComponent(state.tenant.key)}/calls?call_spec_id=${encodeURIComponent(state.callSpec.id)}`),
            }]
          : []),
      ]}
    />
  );
  const callIdentity = (
    <CallIdentity
      callId={state.callId}
      callSpecRevision={state.callSpecRevision}
    />
  );
  const callContext = (
    <div className="flex min-w-0 items-center gap-3">
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
            header={header}
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
        className="w-full"
      >
        <h1 className="sr-only">Call details</h1>
        <div className="bg-[var(--admin-panel)] px-4 py-1 text-[var(--admin-muted)]">{header}</div>
        <div className="px-4 py-3">
          <div className="mb-4">{callIdentity}</div>
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
        </div>
      </main>
    </AdminShell>
  );
}
