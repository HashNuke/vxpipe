import { AdminShell } from "./AdminShell";
import { PageHeader } from "./PageHeader";
import { PageNotice } from "./PageNotice";
import { Pagination } from "./Pagination";
import { TenantList } from "./TenantList";
import { TenantListSkeleton } from "./TenantListSkeleton";
import type { TenantsPageState } from "./tenantTypes";

export function TenantsPage({
  state,
  theme = "dark",
  onSelectTenant,
  onPreviousPage,
  onNextPage,
}: {
  state: TenantsPageState;
  theme?: "dark" | "light";
  onSelectTenant?: (tenantKey: string) => void;
  onPreviousPage?: () => void;
  onNextPage?: () => void;
}) {
  return (
    <AdminShell theme={theme}>
      <main
        aria-busy={state.status === "loading" ? "true" : undefined}
        className="mx-auto w-full max-w-[1600px] px-4 py-6 sm:px-6 sm:py-8"
      >
        <PageHeader
          description="Choose a tenant to inspect its call definitions and calls."
          title="Tenants"
        />
        <section
          aria-label="Tenant directory"
          className="overflow-hidden rounded-sm border border-[var(--admin-line)] bg-[var(--admin-panel)]"
        >
          {state.status === "loading" ? <TenantListSkeleton /> : null}
          {state.status === "unavailable" ? (
            <PageNotice
              kind="unavailable"
              message={state.message}
              title="Tenants unavailable"
            />
          ) : null}
          {state.status === "ready" && state.tenants.length === 0 ? (
            <PageNotice
              kind="empty"
              message="Create a tenant through the trusted administration workflow, then return here."
              title="No tenants yet"
            />
          ) : null}
          {state.status === "ready" && state.tenants.length > 0 ? (
            <>
              <TenantList
                onSelectTenant={onSelectTenant}
                tenants={state.tenants}
              />
              {state.pagination ? (
                <Pagination
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
