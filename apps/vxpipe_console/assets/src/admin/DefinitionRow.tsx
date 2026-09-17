import { ArrowUpRight } from "lucide-react";
import type { MouseEvent } from "react";

import { DefinitionStatusBadge } from "./DefinitionStatusBadge";
import type { DefinitionSummary, TenantContext } from "./definitionTypes";
import { formatAdminDate } from "./formatAdminDate";
import { shouldInterceptNavigation } from "./shouldInterceptNavigation";

export function DefinitionRow({
  definition,
  tenant,
  onSelect,
}: {
  definition: DefinitionSummary;
  tenant: TenantContext;
  onSelect?: (definitionId: string) => void;
}) {
  const label = definition.name ?? definition.id;
  const href = `/admin/tenants/${encodeURIComponent(tenant.key)}/definitions/${encodeURIComponent(definition.id)}`;

  function handleClick(event: MouseEvent<HTMLAnchorElement>) {
    if (!onSelect || !shouldInterceptNavigation(event)) return;
    event.preventDefault();
    onSelect(definition.id);
  }

  return (
    <li>
      <a
        aria-label={`Open ${label}`}
        className="group grid min-w-0 grid-cols-[minmax(0,1fr)_auto_auto_auto] items-center gap-3 border-t border-[var(--admin-line)] px-3 py-4 text-inherit no-underline transition-colors hover:bg-[var(--admin-soft)] sm:px-4 lg:grid-cols-[minmax(180px,1.2fr)_minmax(160px,1fr)_90px_130px_130px_auto] lg:gap-4"
        href={href}
        onClick={handleClick}
      >
        <span className="min-w-0">
          <span className="block truncate text-sm font-semibold">{label}</span>
          <span className="mt-1 block truncate font-mono text-xs text-[var(--admin-muted)] lg:hidden">
            {definition.id}
          </span>
        </span>
        <span
          className="hidden truncate font-mono text-xs text-[var(--admin-muted)] lg:block"
          title={definition.id}
        >
          {definition.id}
        </span>
        <span className="font-mono text-xs tabular-nums text-[var(--admin-muted)]">
          r{definition.latestRevision}
        </span>
        <DefinitionStatusBadge definition={definition} />
        <time
          className="hidden text-sm text-[var(--admin-muted)] lg:block"
          dateTime={definition.updatedAt}
        >
          {formatAdminDate(definition.updatedAt)}
        </time>
        <ArrowUpRight
          aria-hidden="true"
          className="size-4 text-[var(--admin-muted)] transition-colors group-hover:text-[var(--admin-ink)]"
        />
      </a>
    </li>
  );
}
