import type { ReactNode } from "react";

import { AdminShell } from "./AdminShell";
import { CallList } from "./CallList";
import { CallListSkeleton } from "./CallListSkeleton";
import { CallSpecCombobox } from "./CallSpecCombobox";
import type { DefinitionCallsPageState } from "./callTypes";
import { PageNotice } from "./PageNotice";
import { Pagination } from "./Pagination";
import {
  TenantWorkspaceNavigation,
  type TenantDestination,
} from "./TenantWorkspaceNavigation";

export function DefinitionCallsPage({
  state,
  theme = "dark",
  onSelectTenants,
  onSelectTenant,
  onSelectWorkspace,
  onSelectDefinition,
  callHref,
  onPreviousPage,
  onNextPage,
  headerActions,
  workspaceDestinations,
  linkCallDetails,
}: {
  state: DefinitionCallsPageState;
  theme?: "dark" | "light";
  onSelectTenants?: () => void;
  onSelectTenant?: () => void;
  onSelectWorkspace?: (destination: TenantDestination) => void;
  onSelectDefinition?: (definitionId: string | null) => void;
  callHref?: (callId: string) => string;
  onPreviousPage?: () => void;
  onNextPage?: () => void;
  headerActions?: ReactNode;
  workspaceDestinations?: TenantDestination[];
  linkCallDetails?: boolean;
}) {
  const selectedDefinition = state.selectedDefinitionId
    ? state.definitions.find(({ id }) => id === state.selectedDefinitionId)
    : null;
  const unknownFilter = Boolean(
    state.selectedDefinitionId && !selectedDefinition,
  );

  return (
    <AdminShell
      breadcrumbs={[
        { label: "Tenants", href: "/admin", onSelect: onSelectTenants },
        {
          label: state.tenant.name,
          href: `/admin/tenants/${encodeURIComponent(state.tenant.key)}`,
          onSelect: onSelectTenant,
        },
      ]}
      headerActions={headerActions}
      theme={theme}
    >
      <main
        aria-busy={state.status === "loading" ? "true" : undefined}
        className="mx-auto w-full max-w-[1600px] px-4 pb-6 sm:px-6"
      >
        <h1 className="sr-only">Calls</h1>
        <TenantWorkspaceNavigation
          active="calls"
          destinations={workspaceDestinations}
          onSelect={onSelectWorkspace}
          tenant={state.tenant}
        />
        <div className="mb-4 flex flex-wrap items-end gap-3">
          <div className="grid w-full min-w-0 max-w-full gap-1.5 text-xs font-semibold text-[var(--admin-muted)] sm:w-80">
            <span>Call spec</span>
            <CallSpecCombobox
              onSelect={onSelectDefinition}
              options={state.definitions}
              selectedId={state.selectedDefinitionId}
              unknownSelection={unknownFilter}
            />
          </div>
          <button
            className="h-10 rounded-sm border border-[var(--admin-line)] bg-transparent px-3 text-sm font-semibold text-[var(--admin-muted)] hover:bg-[var(--admin-soft)] hover:text-[var(--admin-ink)] disabled:opacity-40"
            disabled={!state.selectedDefinitionId}
            onClick={() => onSelectDefinition?.(null)}
            type="button"
          >
            Show all calls
          </button>
          {state.definitionOptionsTruncated ? (
            <p className="basis-full text-xs text-[var(--admin-muted)]">
              Showing the first 100 call specs. Open Call definitions to find
              another.
            </p>
          ) : null}
        </div>
        <section aria-label="Call directory" className="overflow-hidden">
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
              message="This call spec is not available for this tenant. Show all calls or choose another call spec."
              title="Unknown call spec"
            />
          ) : null}
          {state.status === "ready" &&
          !unknownFilter &&
          state.calls.length === 0 ? (
            <PageNotice
              kind="empty"
              message={
                selectedDefinition
                  ? "Calls using this call spec will appear here."
                  : "Calls for this tenant will appear here."
              }
              title={selectedDefinition ? "No matching calls" : "No calls yet"}
            />
          ) : null}
          {state.status === "ready" &&
          !unknownFilter &&
          state.calls.length > 0 ? (
            <>
              <CallList
                calls={state.calls}
                linkCallDetails={linkCallDetails}
                callHref={callHref}
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
