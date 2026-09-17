import { AdminShell } from "./AdminShell";
import { Breadcrumbs } from "./Breadcrumbs";
import { DefinitionList } from "./DefinitionList";
import { DefinitionListSkeleton } from "./DefinitionListSkeleton";
import type { TenantDefinitionsPageState } from "./definitionTypes";
import { PageHeader } from "./PageHeader";
import { PageNotice } from "./PageNotice";
import { Pagination } from "./Pagination";
import { TenantWorkspaceNavigation } from "./TenantWorkspaceNavigation";

export function TenantDefinitionsPage({
  state,
  theme = "dark",
  onSelectTenants,
  onSelectDefinition,
  onSelectWorkspace,
  onPreviousPage,
  onNextPage,
}: {
  state: TenantDefinitionsPageState;
  theme?: "dark" | "light";
  onSelectTenants?: () => void;
  onSelectDefinition?: (definitionId: string) => void;
  onSelectWorkspace?: (destination: "definitions" | "calls") => void;
  onPreviousPage?: () => void;
  onNextPage?: () => void;
}) {
  return (
    <AdminShell theme={theme}>
      <main
        aria-busy={state.status === "loading" ? "true" : undefined}
        className="mx-auto w-full max-w-[1600px] px-4 py-6 sm:px-6 sm:py-8"
      >
        <Breadcrumbs
          items={[
            { label: "Tenants", href: "/admin", onSelect: onSelectTenants },
            { label: state.tenant.name },
          ]}
        />
        <TenantWorkspaceNavigation
          active="definitions"
          onSelect={onSelectWorkspace}
          tenant={state.tenant}
        />
        <PageHeader
          description={`Published and draft definitions for ${state.tenant.name}.`}
          title="Call definitions"
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
