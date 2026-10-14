import { ArrowUpRight } from "lucide-react";

import { CallStateBadge } from "./CallStateBadge";
import type { CallDirectoryItem } from "./callTypes";
import type { TenantContext } from "./callSpecTypes";
import { formatCallDuration } from "./formatCallDuration";
import {
  formatAdminLocalTimestamp,
  formatCallTimestamp,
} from "./formatAdminTimestamp";

export function CallRow({
  call,
  tenant,
  href,
  linkDetails = true,
}: {
  call: CallDirectoryItem;
  tenant: TenantContext;
  href?: string;
  linkDetails?: boolean;
}) {
  const content = (
    <>
      <span className="min-w-0">
        <span
          className="block truncate font-mono text-sm font-semibold"
          title={call.id}
        >
          {call.id}
        </span>
        <span className="mt-1 flex min-w-0 items-baseline gap-2 text-xs text-[var(--admin-muted)]">
          <span className="truncate" title={call.callSpecName ?? call.callSpecId}>
            {call.callSpecName ?? call.callSpecId}
          </span>
          <span className="shrink-0">v{call.callSpecRevision}</span>
        </span>
      </span>
      <span>
        <CallStateBadge state={call.state} />
      </span>
      <span className="min-w-0 tabular-nums">
        <time className="block whitespace-nowrap text-sm" dateTime={call.createdAt} title={formatAdminLocalTimestamp(call.createdAt)}>
          {formatCallTimestamp(call.createdAt)}
        </time>
        <span className="mt-1 block text-xs text-[var(--admin-muted)]">
          {formatCallDuration(call.state === "ended" ? call.durationMs : null)}
        </span>
      </span>
      {linkDetails ? (
        <ArrowUpRight
          aria-hidden="true"
          className="size-4 text-[var(--admin-muted)] transition-colors group-hover:text-[var(--admin-ink)]"
        />
      ) : (
        <span aria-hidden="true" />
      )}
    </>
  );

  const rowClass = `grid min-w-0 grid-cols-[minmax(260px,1fr)_104px_210px_16px] items-center gap-4 px-4 py-4 text-inherit no-underline${linkDetails ? " group transition-colors hover:bg-[var(--admin-soft)]" : ""}`;

  return (
    <li>
      {linkDetails ? (
        <a
          aria-label={`Open call ${call.id} (opens in a new tab)`}
          className={rowClass}
          href={
            href ??
            `/admin/tenants/${encodeURIComponent(tenant.key)}/calls/${encodeURIComponent(call.id)}`
          }
          rel="noopener noreferrer"
          target="_blank"
          title="Open call in a new tab"
        >
          {content}
        </a>
      ) : (
        <div className={rowClass}>{content}</div>
      )}
    </li>
  );
}
