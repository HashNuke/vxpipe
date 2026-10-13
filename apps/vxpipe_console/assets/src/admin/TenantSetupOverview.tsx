import { useState } from "react";
import { TenantDirectoryView } from "./navigation/TenantDirectoryView";
import type { SetupProvider, SetupConnection, SetupTenant } from "./setupCatalog";

// Compatibility presentation for sample-setup journeys; the canonical directory
// and its permission projection live in WorkspacePages.
export function TenantSetupOverview({ items, onSetup, onOpen, onCreate }: {
  providers?: SetupProvider[];
  items: Array<{ tenant: SetupTenant; connections: SetupConnection[]; hasCallSpecs: boolean }>;
  onSetup: (tenant: SetupTenant) => void; onOpen: (tenant: SetupTenant) => void; onCreate: () => void;
}) {
  const [query, setQuery] = useState("");
  return <TenantDirectoryView as="section" title="Tenants" state="ready" query={query} onQueryChange={setQuery} canCreate
    tenants={items.filter(({ tenant }) => `${tenant.name} ${tenant.key}`.toLowerCase().includes(query.toLowerCase())).map(({ tenant }) => ({ ...tenant, canSetup: true }))}
    link={(href, children, label) => <a href={`#${href}`} aria-label={label} onClick={event => {
      event.preventDefault();
      if (href === "/tenants/new") { onCreate(); return; }
      const tenant = items.find(item => href.startsWith(`/t/${item.tenant.key}/`))?.tenant;
      if (tenant) { if (href.endsWith("/services")) onSetup(tenant); else onOpen(tenant); }
    }}>{children}</a>} />;
}
