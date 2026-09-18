import type { MouseEvent } from "react";

import { CallSpecStatusBadge } from "./CallSpecStatusBadge";
import type { CallSpecSummary, TenantContext } from "./callSpecTypes";
import { formatAdminDate } from "./formatAdminDate";
import { shouldInterceptNavigation } from "./shouldInterceptNavigation";

export function CallSpecRow({
  callSpec,
  tenant,
  onSelect,
  linkCalls = true,
}: {
  callSpec: CallSpecSummary;
  tenant: TenantContext;
  onSelect?: (callSpecId: string) => void;
  linkCalls?: boolean;
}) {
  const label = callSpec.name ?? callSpec.id;
  const href = `/admin/tenants/${encodeURIComponent(tenant.key)}/calls?call_spec_id=${encodeURIComponent(callSpec.id)}`;

  function handleClick(event: MouseEvent<HTMLAnchorElement>) {
    if (!onSelect || !shouldInterceptNavigation(event)) return;
    event.preventDefault();
    onSelect(callSpec.id);
  }

  return (
    <tr className="border-t border-[var(--admin-row-line)] transition-colors first:border-t-0 hover:bg-[var(--admin-soft)]">
      <th className="truncate px-4 py-4 text-sm font-semibold" scope="row" title={label}>
        {label}
      </th>
      <td className="truncate px-4 py-4 font-mono text-xs text-[var(--admin-muted)]" title={callSpec.id}>
        {callSpec.id}
      </td>
      <td className="px-4 py-4 font-mono text-xs tabular-nums text-[var(--admin-muted)]">
        v{callSpec.latestRevision}
      </td>
      <td className="px-4 py-4 text-right font-mono text-xs tabular-nums">
        {linkCalls ? (
          <a
            aria-label={`View ${callSpec.callCount} calls for ${label}`}
            className="rounded-sm text-[var(--admin-blue)] underline-offset-4 hover:underline"
            href={href}
            onClick={handleClick}
          >
            {callSpec.callCount.toLocaleString()}
          </a>
        ) : (
          callSpec.callCount.toLocaleString()
        )}
      </td>
      <td className="px-4 py-4">
        <CallSpecStatusBadge callSpec={callSpec} />
      </td>
      <td className="px-4 py-4">
        <time
          className="text-sm text-[var(--admin-muted)]"
          dateTime={callSpec.updatedAt}
        >
          {formatAdminDate(callSpec.updatedAt)}
        </time>
      </td>
    </tr>
  );
}
