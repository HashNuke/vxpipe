import { ArrowUpRight } from "lucide-react";

import { formatAdminDate } from "./formatAdminDate";
import { shouldInterceptNavigation } from "./shouldInterceptNavigation";
import type { TenantSummary } from "./tenantTypes";

export function TenantRow({
  tenant,
  onSelect,
}: {
  tenant: TenantSummary;
  onSelect?: (tenantKey: string) => void;
}) {
  const href = `/admin/tenants/${encodeURIComponent(tenant.key)}`;

  function handleClick(event: React.MouseEvent<HTMLAnchorElement>) {
    if (!onSelect || !shouldInterceptNavigation(event)) return;
    event.preventDefault();
    onSelect(tenant.key);
  }

  return (
    <li>
      <a
        aria-label={`Open ${tenant.name}`}
        className="group grid min-w-0 grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)_auto] items-center gap-4 px-3 py-4 text-inherit no-underline transition-colors hover:bg-[var(--admin-soft)] sm:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)_minmax(120px,0.55fr)_auto] sm:px-4"
        href={href}
        onClick={handleClick}
      >
        <span className="min-w-0">
          <span className="block truncate text-sm font-semibold">{tenant.name}</span>
          <span className="mt-1 block text-xs text-[var(--admin-muted)] sm:hidden">
            {formatAdminDate(tenant.createdAt)}
          </span>
        </span>
        <span
          className="truncate font-mono text-xs text-[var(--admin-muted)]"
          title={tenant.key}
        >
          {tenant.key}
        </span>
        <time
          className="hidden text-sm text-[var(--admin-muted)] sm:block"
          dateTime={tenant.createdAt}
        >
          {formatAdminDate(tenant.createdAt)}
        </time>
        <span>
          <ArrowUpRight
            aria-hidden="true"
            className="size-4 text-[var(--admin-muted)] transition-colors group-hover:text-[var(--admin-ink)]"
          />
        </span>
      </a>
    </li>
  );
}
