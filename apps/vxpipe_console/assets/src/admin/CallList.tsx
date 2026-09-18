import { CallRow } from "./CallRow";
import type { CallDirectoryItem } from "./callTypes";
import type { TenantContext } from "./definitionTypes";

export function CallList({
  calls,
  tenant,
  callHref,
  linkCallDetails,
}: {
  calls: CallDirectoryItem[];
  tenant: TenantContext;
  callHref?: (callId: string) => string;
  linkCallDetails?: boolean;
}) {
  return (
    <div aria-label="Calls" className="overflow-x-auto">
      <div className="min-w-[760px]">
        <div
          aria-hidden="true"
          className="grid grid-cols-[minmax(220px,1.35fr)_minmax(180px,1fr)_104px_190px_16px] gap-4 border-b border-[var(--admin-line)] px-4 py-3 font-mono text-xs font-bold uppercase tracking-[0.05em] text-[var(--admin-muted)]"
        >
          <span>ID</span>
          <span>Call spec</span>
          <span>State</span>
          <span>Time</span>
          <span className="sr-only">Open</span>
        </div>
        <ul className="m-0 list-none divide-y divide-[var(--admin-row-line)] p-0">
          {calls.map((call) => (
            <CallRow
              call={call}
              key={call.id}
              linkDetails={linkCallDetails}
              href={callHref?.(call.id)}
              tenant={tenant}
            />
          ))}
        </ul>
      </div>
    </div>
  );
}
