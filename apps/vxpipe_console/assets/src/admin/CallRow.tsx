import { ArrowUpRight } from "lucide-react";
import type { MouseEvent } from "react";

import { ArchiveStateBadge } from "./ArchiveStateBadge";
import { CallStateBadge } from "./CallStateBadge";
import type { CallSummary } from "./callTypes";
import type { TenantContext } from "./definitionTypes";
import { formatAdminTimestamp } from "./formatAdminTimestamp";
import { formatCallDuration } from "./formatCallDuration";
import { humanizeIdentifier } from "./humanizeIdentifier";
import { shouldInterceptNavigation } from "./shouldInterceptNavigation";

export function CallRow({
  call,
  tenant,
  onSelect,
  linkDetails = true,
}: {
  call: CallSummary;
  tenant: TenantContext;
  onSelect?: (callId: string) => void;
  linkDetails?: boolean;
}) {
  const href = `/admin/tenants/${encodeURIComponent(tenant.key)}/calls/${encodeURIComponent(call.id)}`;
  const duration = formatCallDuration(call.startedAt, call.endedAt);
  const compactTimestamp = call.startedAt
    ? formatAdminTimestamp(call.startedAt)
    : `Created ${formatAdminTimestamp(call.createdAt)}`;

  function handleClick(event: MouseEvent<HTMLAnchorElement>) {
    if (!onSelect || !shouldInterceptNavigation(event)) return;
    event.preventDefault();
    onSelect(call.id);
  }

  const content = (
    <>
      <span className="min-w-0">
        <span className="block truncate font-mono text-sm font-semibold" title={call.id}>
          {call.id}
        </span>
        <span className="mt-1 block truncate text-xs text-[var(--admin-muted)] xl:hidden">
          {call.definitionName ?? call.definitionId} · v{call.definitionRevision} ·{" "}
          {compactTimestamp}
          {duration ? ` · ${duration}` : ""}
        </span>
      </span>
      <span
        className="hidden truncate text-xs text-[var(--admin-muted)] xl:block"
        title={call.definitionName ?? call.definitionId}
      >
        {call.definitionName ?? call.definitionId}
      </span>
      <span className="hidden font-mono text-xs tabular-nums text-[var(--admin-muted)] xl:block">
        v{call.definitionRevision}
      </span>
      <span className="min-w-0">
        <CallStateBadge state={call.state} />
        {call.terminalReason ? (
          <span className="mt-1 hidden truncate text-xs text-[var(--admin-muted)] xl:block">
            {humanizeIdentifier(call.terminalReason)}
          </span>
        ) : null}
      </span>
      {call.startedAt ? (
        <time
          className="hidden text-sm text-[var(--admin-muted)] xl:block"
          dateTime={call.startedAt}
        >
          {formatAdminTimestamp(call.startedAt)}
        </time>
      ) : (
        <span className="hidden text-sm text-[var(--admin-muted)] xl:block">—</span>
      )}
      <span className="hidden font-mono text-xs tabular-nums text-[var(--admin-muted)] xl:block">
        {duration ?? "—"}
      </span>
      <ArchiveStateBadge state={call.archiveState} />
      {linkDetails ? (
        <ArrowUpRight
          aria-hidden="true"
          className="size-4 text-[var(--admin-muted)] transition-colors group-hover:text-[var(--admin-ink)]"
        />
      ) : (
        <span aria-hidden="true" />
      )}
      {call.terminalReason ? (
        <span className="col-span-4 truncate text-xs text-[var(--admin-muted)] xl:hidden">
          {humanizeIdentifier(call.terminalReason)}
        </span>
      ) : null}
    </>
  );

  const rowClass = `grid min-w-0 grid-cols-[minmax(0,1fr)_88px_104px_16px] items-center gap-3 border-t border-[var(--admin-line)] px-3 py-4 text-inherit no-underline sm:px-4 xl:grid-cols-[minmax(210px,1.25fr)_minmax(150px,1fr)_62px_110px_170px_80px_110px_16px] xl:gap-4${linkDetails ? " group transition-colors hover:bg-[var(--admin-soft)]" : ""}`;

  return (
    <li>
      {linkDetails ? (
        <a
          aria-label={`Open call ${call.id}`}
          className={rowClass}
          href={href}
          onClick={handleClick}
        >
          {content}
        </a>
      ) : (
        <div className={rowClass}>{content}</div>
      )}
    </li>
  );
}
