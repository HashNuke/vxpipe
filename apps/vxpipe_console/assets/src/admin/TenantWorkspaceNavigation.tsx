import type { MouseEvent, ReactNode } from "react";

import type { TenantContext } from "./callSpecTypes";
import { shouldInterceptNavigation } from "./shouldInterceptNavigation";

export type TenantDestination = "call-specs" | "calls" | "services";

export function TenantWorkspaceNavigation({
  active,
  actions,
  tenant,
  onSelect,
  destinations = ["call-specs", "calls", "services"],
}: {
  active: TenantDestination;
  actions?: ReactNode;
  tenant: TenantContext;
  onSelect?: (destination: TenantDestination) => void;
  destinations?: TenantDestination[];
}) {
  return (
    <div className="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between sm:gap-6">
      <nav aria-label="Tenant workspace" className="min-w-0 sm:flex-1">
        <div className="flex gap-6">
          {destinations.map((destination) => {
            const label = destination === "call-specs" ? "Call specs" : destination === "calls" ? "Calls" : "Services";
            const href = `/admin/tenants/${encodeURIComponent(tenant.key)}/${destination}`;

            return (
              <a
                aria-current={active === destination ? "page" : undefined}
                className="inline-flex min-h-12 shrink-0 items-center border-b-2 border-transparent text-sm font-semibold text-[var(--admin-muted)] no-underline transition-colors hover:text-[var(--admin-ink)] aria-[current=page]:border-[var(--admin-ink)] aria-[current=page]:text-[var(--admin-ink)]"
                href={href}
                key={destination}
                onClick={(event: MouseEvent<HTMLAnchorElement>) => {
                  if (!onSelect || !shouldInterceptNavigation(event)) return;
                  event.preventDefault();
                  onSelect(destination);
                }}
              >
                {label}
              </a>
            );
          })}
        </div>
      </nav>
      {actions ? <div className="flex shrink-0 justify-end sm:py-1.5">{actions}</div> : null}
    </div>
  );
}
