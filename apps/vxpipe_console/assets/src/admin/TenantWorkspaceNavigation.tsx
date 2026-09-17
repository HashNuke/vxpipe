import type { MouseEvent } from "react";

import type { TenantContext } from "./definitionTypes";
import { shouldInterceptNavigation } from "./shouldInterceptNavigation";

export type TenantDestination = "definitions" | "calls" | "services";

export function TenantWorkspaceNavigation({
  active,
  tenant,
  onSelect,
  destinations = ["definitions", "calls", "services"],
}: {
  active: TenantDestination;
  tenant: TenantContext;
  onSelect?: (destination: TenantDestination) => void;
  destinations?: TenantDestination[];
}) {
  return (
    <nav aria-label="Tenant workspace" className="mb-6 border-b border-[var(--admin-line)]">
      <div className="flex gap-6">
        {destinations.map((destination) => {
          const label = destination === "definitions" ? "Call definitions" : destination === "calls" ? "Calls" : "Services";
          const href = `/admin/tenants/${encodeURIComponent(tenant.key)}/${destination}`;

          return (
            <a
              aria-current={active === destination ? "page" : undefined}
              className="border-b-2 border-transparent pb-3 text-sm font-semibold text-[var(--admin-muted)] no-underline transition-colors hover:text-[var(--admin-ink)] aria-[current=page]:border-[var(--admin-ink)] aria-[current=page]:text-[var(--admin-ink)]"
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
  );
}
