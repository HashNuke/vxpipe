import { CallSpecRow } from "./CallSpecRow";
import type { CallSpecSummary, TenantContext } from "./callSpecTypes";

export function CallSpecList({
  callSpecs,
  tenant,
  onSelectCallSpec,
  linkCalls,
}: {
  callSpecs: CallSpecSummary[];
  tenant: TenantContext;
  onSelectCallSpec?: (callSpecId: string) => void;
  linkCalls?: boolean;
}) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[900px] table-fixed border-collapse text-left">
        <caption className="sr-only">Call specs</caption>
        <colgroup>
          <col className="w-[28%]" />
          <col className="w-[25%]" />
          <col className="w-[10%]" />
          <col className="w-[9%]" />
          <col className="w-[14%]" />
          <col className="w-[14%]" />
        </colgroup>
        <thead className="border-b border-[var(--admin-line)]">
          <tr className="font-mono text-xs font-bold uppercase tracking-[0.05em] text-[var(--admin-muted)]">
            <th className="px-4 py-3" scope="col">Name</th>
            <th className="px-4 py-3" scope="col">ID</th>
            <th className="px-4 py-3" scope="col">Version</th>
            <th className="px-4 py-3 text-right" scope="col">Calls</th>
            <th className="px-4 py-3" scope="col">State</th>
            <th className="px-4 py-3" scope="col">Updated</th>
          </tr>
        </thead>
        <tbody>
          {callSpecs.map((callSpec) => (
            <CallSpecRow
              callSpec={callSpec}
              key={callSpec.id}
              linkCalls={linkCalls}
              onSelect={onSelectCallSpec}
              tenant={tenant}
            />
          ))}
        </tbody>
      </table>
    </div>
  );
}
