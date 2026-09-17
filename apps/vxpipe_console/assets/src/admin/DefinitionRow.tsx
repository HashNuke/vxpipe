import type { MouseEvent } from "react";

import { DefinitionStatusBadge } from "./DefinitionStatusBadge";
import type { DefinitionSummary, TenantContext } from "./definitionTypes";
import { formatAdminDate } from "./formatAdminDate";
import { shouldInterceptNavigation } from "./shouldInterceptNavigation";

export function DefinitionRow({
  definition,
  tenant,
  onSelect,
  linkCalls = true,
}: {
  definition: DefinitionSummary;
  tenant: TenantContext;
  onSelect?: (definitionId: string) => void;
  linkCalls?: boolean;
}) {
  const label = definition.name ?? definition.id;
  const href = `/admin/tenants/${encodeURIComponent(tenant.key)}/calls?definition_id=${encodeURIComponent(definition.id)}`;

  function handleClick(event: MouseEvent<HTMLAnchorElement>) {
    if (!onSelect || !shouldInterceptNavigation(event)) return;
    event.preventDefault();
    onSelect(definition.id);
  }

  return (
    <tr className="border-t border-[var(--admin-line)] transition-colors hover:bg-[var(--admin-soft)]">
      <th className="truncate px-4 py-4 text-sm font-semibold" scope="row" title={label}>
        {label}
      </th>
      <td className="truncate px-4 py-4 font-mono text-xs text-[var(--admin-muted)]" title={definition.id}>
        {definition.id}
      </td>
      <td className="px-4 py-4 font-mono text-xs tabular-nums text-[var(--admin-muted)]">
        v{definition.latestRevision}
      </td>
      <td className="px-4 py-4 text-right font-mono text-xs tabular-nums">
        {linkCalls ? (
          <a
            aria-label={`View ${definition.callCount} calls for ${label}`}
            className="rounded-sm text-[var(--admin-blue)] underline-offset-4 hover:underline"
            href={href}
            onClick={handleClick}
          >
            {definition.callCount.toLocaleString()}
          </a>
        ) : (
          definition.callCount.toLocaleString()
        )}
      </td>
      <td className="px-4 py-4">
        <DefinitionStatusBadge definition={definition} />
      </td>
      <td className="px-4 py-4">
        <time
          className="text-sm text-[var(--admin-muted)]"
          dateTime={definition.updatedAt}
        >
          {formatAdminDate(definition.updatedAt)}
        </time>
      </td>
    </tr>
  );
}
