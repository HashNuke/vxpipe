import { CallRow } from "./CallRow";
import type { CallSummary } from "./callTypes";
import type { TenantContext } from "./definitionTypes";

export function CallList({
  calls,
  tenant,
  onSelectCall,
}: {
  calls: CallSummary[];
  tenant: TenantContext;
  onSelectCall?: (callId: string) => void;
}) {
  return (
    <div aria-label="Calls">
      <div
        aria-hidden="true"
        className="grid grid-cols-[minmax(0,1fr)_88px_104px_16px] gap-3 px-3 py-3 font-mono text-xs font-bold uppercase tracking-[0.05em] text-[var(--admin-muted)] sm:px-4 lg:grid-cols-[minmax(220px,1.4fr)_70px_120px_180px_90px_120px_16px] lg:gap-4"
      >
        <span>Call</span>
        <span className="hidden lg:block">Revision</span>
        <span>State</span>
        <span className="hidden lg:block">Started</span>
        <span className="hidden lg:block">Duration</span>
        <span>Archive</span>
        <span className="sr-only">Open</span>
      </div>
      <ul className="m-0 list-none p-0">
        {calls.map((call) => (
          <CallRow
            call={call}
            key={call.id}
            onSelect={onSelectCall}
            tenant={tenant}
          />
        ))}
      </ul>
    </div>
  );
}
