import { TenantRow } from "./TenantRow";
import type { TenantSummary } from "./tenantTypes";

export function TenantList({
  tenants,
  onSelectTenant,
}: {
  tenants: TenantSummary[];
  onSelectTenant?: (tenantKey: string) => void;
}) {
  return (
    <div aria-label="Tenants">
      <div
        aria-hidden="true"
        className="grid grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)_auto] gap-4 border-b border-[var(--admin-line)] px-3 py-3 font-mono text-xs font-bold uppercase tracking-[0.05em] text-[var(--admin-muted)] sm:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)_minmax(120px,0.55fr)_auto] sm:px-4"
      >
        <span>Tenant</span>
        <span>Key</span>
        <span className="hidden sm:block">Created</span>
        <span className="sr-only">Open</span>
      </div>
      <ul className="m-0 list-none divide-y divide-[var(--admin-row-line)] p-0">
        {tenants.map((tenant) => (
          <TenantRow
            key={tenant.key}
            tenant={tenant}
            onSelect={onSelectTenant}
          />
        ))}
      </ul>
    </div>
  );
}
