import { AdminShell } from "./AdminShell";
import { Breadcrumbs } from "./Breadcrumbs";
import { CallList } from "./CallList";
import { CallListSkeleton } from "./CallListSkeleton";
import type { DefinitionCallsPageState } from "./callTypes";
import { PageHeader } from "./PageHeader";
import { PageNotice } from "./PageNotice";
import { Pagination } from "./Pagination";
import { TenantWorkspaceNavigation } from "./TenantWorkspaceNavigation";

export function DefinitionCallsPage({
  state,
  theme = "dark",
  onSelectTenants,
  onSelectTenant,
  onSelectWorkspace,
  onSelectDefinition,
  onSelectCall,
  onPreviousPage,
  onNextPage,
}: {
  state: DefinitionCallsPageState;
  theme?: "dark" | "light";
  onSelectTenants?: () => void;
  onSelectTenant?: () => void;
  onSelectWorkspace?: (destination: "definitions" | "calls") => void;
  onSelectDefinition?: (definitionId: string | null) => void;
  onSelectCall?: (callId: string) => void;
  onPreviousPage?: () => void;
  onNextPage?: () => void;
}) {
  const selectedDefinition = state.selectedDefinitionId
    ? state.definitions.find(({ id }) => id === state.selectedDefinitionId)
    : null;
  const unknownFilter = Boolean(state.selectedDefinitionId && !selectedDefinition);

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
            { label: "Calls" },
          ]}
        />
        <TenantWorkspaceNavigation
          active="calls"
          onSelect={onSelectWorkspace}
          tenant={state.tenant}
        />
        <PageHeader title="Calls" />
        <div className="mb-4 flex flex-wrap items-end gap-3">
          <label className="grid w-full min-w-0 max-w-full gap-1.5 text-xs font-semibold text-[var(--admin-muted)] sm:w-80">
            Call definition
            <select
              className="h-10 w-full min-w-0 max-w-full rounded-sm border border-[var(--admin-line)] bg-[var(--admin-panel)] px-3 text-sm text-[var(--admin-ink)]"
              onChange={(event) => onSelectDefinition?.(event.target.value || null)}
              value={state.selectedDefinitionId ?? ""}
            >
              <option value="">All call definitions</option>
              {unknownFilter ? (
                <option value={state.selectedDefinitionId ?? ""}>Unknown definition</option>
              ) : null}
              {state.definitions.map((definition) => (
                <option key={definition.id} value={definition.id}>
                  {definition.name ?? definition.id}
                </option>
              ))}
            </select>
          </label>
          <button
            className="h-10 rounded-sm border border-[var(--admin-line)] bg-transparent px-3 text-sm font-semibold text-[var(--admin-muted)] hover:bg-[var(--admin-soft)] hover:text-[var(--admin-ink)] disabled:opacity-40"
            disabled={!state.selectedDefinitionId}
            onClick={() => onSelectDefinition?.(null)}
            type="button"
          >
            Show all calls
          </button>
        </div>
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
          {state.status === "ready" && unknownFilter ? (
            <PageNotice
              kind="unavailable"
              message="This call definition is not available for this tenant. Show all calls or choose another definition."
              title="Unknown call definition"
            />
          ) : null}
          {state.status === "ready" && !unknownFilter && state.calls.length === 0 ? (
            <PageNotice
              kind="empty"
              message={selectedDefinition ? "Calls using this definition will appear here." : "Calls for this tenant will appear here."}
              title={selectedDefinition ? "No matching calls" : "No calls yet"}
            />
          ) : null}
          {state.status === "ready" && !unknownFilter && state.calls.length > 0 ? (
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
