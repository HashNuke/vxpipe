import { AdminShell } from "./AdminShell";
import { Breadcrumbs } from "./Breadcrumbs";
import { CallList } from "./CallList";
import { CallListSkeleton } from "./CallListSkeleton";
import type { DefinitionCallsPageState } from "./callTypes";
import { PageHeader } from "./PageHeader";
import { PageNotice } from "./PageNotice";
import { Pagination } from "./Pagination";

export function DefinitionCallsPage({
  state,
  theme = "dark",
  onSelectTenants,
  onSelectTenant,
  onSelectCall,
  onPreviousPage,
  onNextPage,
}: {
  state: DefinitionCallsPageState;
  theme?: "dark" | "light";
  onSelectTenants?: () => void;
  onSelectTenant?: () => void;
  onSelectCall?: (callId: string) => void;
  onPreviousPage?: () => void;
  onNextPage?: () => void;
}) {
  const definitionLabel = state.definition.name ?? state.definition.id;
  const publication = state.definition.publishedRevision
    ? `published r${state.definition.publishedRevision}`
    : "not published";

  return (
    <AdminShell theme={theme}>
      <main
        aria-busy={state.status === "loading" ? "true" : undefined}
        className="mx-auto w-full max-w-[1600px] px-4 py-6 sm:px-6 sm:py-8"
      >
        <Breadcrumbs
          items={[
            { label: "Tenants", href: "/admin", onSelect: onSelectTenants },
            {
              label: state.tenant.name,
              href: `/admin/tenants/${encodeURIComponent(state.tenant.key)}`,
              onSelect: onSelectTenant,
            },
            { label: definitionLabel },
          ]}
        />
        <PageHeader
          description={`Across all revisions of ${state.definition.id} · ${publication}.`}
          title="Calls"
        />
        <section
          aria-label="Call directory"
          className="overflow-hidden rounded-sm border border-[var(--admin-line)] bg-[var(--admin-panel)]"
        >
          {state.status === "loading" ? <CallListSkeleton /> : null}
          {state.status === "unavailable" ? (
            <PageNotice
              kind="unavailable"
              message={state.message}
              title="Calls unavailable"
            />
          ) : null}
          {state.status === "ready" && state.calls.length === 0 ? (
            <PageNotice
              kind="empty"
              message="Calls using this definition will appear here."
              title="No calls yet"
            />
          ) : null}
          {state.status === "ready" && state.calls.length > 0 ? (
            <>
              <CallList
                calls={state.calls}
                onSelectCall={onSelectCall}
                tenant={state.tenant}
              />
              {state.pagination ? (
                <Pagination
                  ariaLabel="Call pages"
                  onNext={onNextPage}
                  onPrevious={onPreviousPage}
                  pagination={state.pagination}
                />
              ) : null}
            </>
          ) : null}
        </section>
      </main>
    </AdminShell>
  );
}
