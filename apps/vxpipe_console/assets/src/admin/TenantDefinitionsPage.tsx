import type { ReactNode } from "react";

import { AdminShell } from "./AdminShell";
import { DefinitionList } from "./DefinitionList";
import { DefinitionListSkeleton } from "./DefinitionListSkeleton";
import type { TenantDefinitionsPageState } from "./definitionTypes";
import { PageNotice } from "./PageNotice";
import { Pagination } from "./Pagination";
import { TenantWorkspaceNavigation, type TenantDestination } from "./TenantWorkspaceNavigation";

export function TenantDefinitionsPage({
  state,
  theme = "dark",
  onSelectTenants,
  onSelectDefinition,
  onSelectWorkspace,
  onPreviousPage,
  onNextPage,
  headerActions,
  workspaceDestinations,
  linkCalls,
}: {
  state: TenantDefinitionsPageState;
  theme?: "dark" | "light";
  onSelectTenants?: () => void;
  onSelectDefinition?: (definitionId: string) => void;
  onSelectWorkspace?: (destination: TenantDestination) => void;
  onPreviousPage?: () => void;
  onNextPage?: () => void;
  headerActions?: ReactNode;
  workspaceDestinations?: TenantDestination[];
  linkCalls?: boolean;
}) {
  return (
    <AdminShell
      breadcrumbs={[
        { label: "Tenants", href: "/admin", onSelect: onSelectTenants },
        { label: state.tenant.name },
      ]}
      headerActions={headerActions}
      theme={theme}
    >
      <main
        aria-busy={state.status === "loading" ? "true" : undefined}
        className="mx-auto w-full max-w-[1600px] px-4 pb-6 sm:px-6"
      >
        <h1 className="sr-only">Call definitions</h1>
        <TenantWorkspaceNavigation
          active="definitions"
          destinations={workspaceDestinations}
          onSelect={onSelectWorkspace}
          tenant={state.tenant}
        />
        <section
          aria-label="Definition directory"
          className="overflow-hidden rounded-sm border border-[var(--admin-line)] bg-[var(--admin-panel)]"
        >
          {state.status === "loading" ? <DefinitionListSkeleton /> : null}
          {state.status === "unavailable" ? (
            <PageNotice
              kind="unavailable"
              message={state.message}
              title="Call definitions unavailable"
            />
          ) : null}
          {state.status === "ready" && state.definitions.length === 0 ? (
            <PageNotice
              kind="empty"
              message="Definitions saved for this tenant will appear here."
              title="No call definitions yet"
            />
          ) : null}
          {state.status === "ready" && state.definitions.length > 0 ? (
            <>
              <DefinitionList
                definitions={state.definitions}
                linkCalls={linkCalls}
                onSelectDefinition={onSelectDefinition}
                tenant={state.tenant}
              />
              {state.pagination ? (
                <Pagination
                  ariaLabel="Definition pages"
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
