import { CallRow } from "./CallRow";
import type { CallSummary } from "./callTypes";
import type { TenantContext } from "./definitionTypes";

export function CallList({
  calls,
  tenant,
  onSelectCall,
  linkCallDetails,
}: {
  calls: CallSummary[];
  tenant: TenantContext;
  onSelectCall?: (callId: string) => void;
  linkCallDetails?: boolean;
}) {
  return (
    <div aria-label="Calls">
      <div
        aria-hidden="true"
        className="grid grid-cols-[minmax(0,1fr)_88px_104px_16px] gap-3 px-3 py-3 font-mono text-xs font-bold uppercase tracking-[0.05em] text-[var(--admin-muted)] sm:px-4 xl:grid-cols-[minmax(210px,1.25fr)_minmax(150px,1fr)_62px_110px_170px_80px_110px_16px] xl:gap-4"
      >
        <span>Call</span>
        <span className="hidden xl:block">Definition</span>
        <span className="hidden xl:block">Version</span>
        <span>State</span>
        <span className="hidden xl:block">Started</span>
        <span className="hidden xl:block">Duration</span>
        <span>Archive</span>
        <span className="sr-only">Open</span>
      </div>
      <ul className="m-0 list-none p-0">
        {calls.map((call) => (
          <CallRow
            call={call}
            key={call.id}
            linkDetails={linkCallDetails}
            onSelect={onSelectCall}
            tenant={tenant}
          />
        ))}
      </ul>
    </div>
  );
}
