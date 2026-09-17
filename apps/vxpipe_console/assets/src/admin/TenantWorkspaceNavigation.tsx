import type { MouseEvent } from "react";

import type { TenantContext } from "./definitionTypes";
import { shouldInterceptNavigation } from "./shouldInterceptNavigation";

type TenantDestination = "definitions" | "calls";

export function TenantWorkspaceNavigation({
  active,
  tenant,
  onSelect,
}: {
  active: TenantDestination;
  tenant: TenantContext;
  onSelect?: (destination: TenantDestination) => void;
}) {
  return (
    <nav aria-label="Tenant workspace" className="mb-6 border-b border-[var(--admin-line)]">
      <div className="flex gap-6">
        {(["definitions", "calls"] as const).map((destination) => {
          const label = destination === "definitions" ? "Call definitions" : "Calls";
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
