import type { ReactNode } from "react";

import { AdminShell } from "./AdminShell";
import { CallSpecList } from "./CallSpecList";
import { CallSpecListSkeleton } from "./CallSpecListSkeleton";
import type { TenantCallSpecsPageState } from "./callSpecTypes";
import { PageNotice } from "./PageNotice";
import { Pagination } from "./Pagination";
import { TenantWorkspaceNavigation, type TenantDestination } from "./TenantWorkspaceNavigation";

export function TenantCallSpecsPage({
  state,
  theme = "dark",
  onSelectTenants,
  onSelectCallSpec,
  onSelectWorkspace,
  onPreviousPage,
  onNextPage,
  headerActions,
  workspaceDestinations,
  linkCalls,
}: {
  state: TenantCallSpecsPageState;
  theme?: "dark" | "light";
  onSelectTenants?: () => void;
  onSelectCallSpec?: (callSpecId: string) => void;
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
        <h1 className="sr-only">Call specs</h1>
        <TenantWorkspaceNavigation
          active="call-specs"
          destinations={workspaceDestinations}
          onSelect={onSelectWorkspace}
          tenant={state.tenant}
        />
        <section
          aria-label="Call spec directory"
          className="overflow-hidden"
        >
          {state.status === "loading" ? <CallSpecListSkeleton /> : null}
          {state.status === "unavailable" ? (
            <PageNotice
              kind="unavailable"
              message={state.message}
              title="Call specs unavailable"
            />
          ) : null}
          {state.status === "ready" && state.callSpecs.length === 0 ? (
            <PageNotice
              kind="empty"
              message="Call specs saved for this tenant will appear here."
              title="No call specs yet"
            />
          ) : null}
          {state.status === "ready" && state.callSpecs.length > 0 ? (
            <>
              <CallSpecList
                callSpecs={state.callSpecs}
                linkCalls={linkCalls}
                onSelectCallSpec={onSelectCallSpec}
                tenant={state.tenant}
              />
              {state.pagination ? (
                <Pagination
                  ariaLabel="Call spec pages"
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
