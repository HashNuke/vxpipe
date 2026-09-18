import { ArrowUpRight } from "lucide-react";

import { CallStateBadge } from "./CallStateBadge";
import type { CallDirectoryItem } from "./callTypes";
import type { TenantContext } from "./definitionTypes";
import { formatAdminRelativeTime } from "./formatAdminRelativeTime";
import {
  formatAdminLocalTimestamp,
  formatAdminTimestamp,
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
      </span>
      <span className="min-w-0">
        <span
          className="block truncate text-sm"
          title={call.definitionName ?? call.definitionId}
        >
          {call.definitionName ?? call.definitionId}
        </span>
        <span className="mt-1 inline-flex rounded-sm bg-[var(--admin-soft)] px-1.5 py-0.5 font-mono text-[0.68rem] font-semibold uppercase tracking-[0.04em] text-[var(--admin-muted)]">
          Version {call.definitionRevision}
        </span>
      </span>
      <span>
        <CallStateBadge state={call.state} />
      </span>
      <time
        className="min-w-0"
        dateTime={call.createdAt}
        title={formatAdminLocalTimestamp(call.createdAt)}
      >
        <span className="block truncate text-sm text-[var(--admin-ink)]">
          {formatAdminTimestamp(call.createdAt)}
        </span>
        <span className="mt-1 block text-xs text-[var(--admin-muted)]">
          {formatAdminRelativeTime(call.createdAt)}
        </span>
      </time>
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

  const rowClass = `grid min-w-0 grid-cols-[minmax(220px,1.35fr)_minmax(180px,1fr)_104px_190px_16px] items-center gap-4 px-4 py-4 text-inherit no-underline${linkDetails ? " group transition-colors hover:bg-[var(--admin-soft)]" : ""}`;

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
