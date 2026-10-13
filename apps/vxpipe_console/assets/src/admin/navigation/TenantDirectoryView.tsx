import type { ReactNode } from "react";
import { ArrowRight, Search } from "lucide-react";
import { formatAdminRelativeTime } from "../formatAdminRelativeTime";

export type DirectoryTenant = { key: string; name: string; createdAt?: string; canSetup?: boolean };
export type DirectoryLink = (href: string, children: ReactNode, label?: string) => ReactNode;
export function DirectorySkeleton({ label = "Loading tenants" }: { label?: string }) {
  return <div role="status" aria-label={label} className="animate-pulse motion-reduce:animate-none"><span className="sr-only">{label}</span>{[0, 1, 2, 3].map(row => <div key={row} className="flex min-h-20 flex-col justify-center gap-3 border-b border-[var(--admin-line)] px-3"><span className="h-4 w-40 max-w-full rounded bg-[var(--admin-soft)]" /><span className="h-3 w-64 max-w-full rounded bg-[var(--admin-soft)]" /></div>)}</div>;
}
export function TenantDirectoryView({ title, state, tenants, query, onQueryChange, canCreate, link, pagination, as: Container = "main" }: {
  as?: "main" | "section"; title: string; state: "ready" | "loading" | "unavailable" | "no-access"; tenants: DirectoryTenant[];
  query: string; onQueryChange: (query: string) => void; canCreate: boolean; link: DirectoryLink; pagination?: ReactNode;
}) {
  return <Container aria-busy={state === "loading" || undefined}><div className="navigation-heading"><div><h1>{title}</h1><p>Choose a tenant to open its workspace.</p></div>{canCreate ? <span className="navigation-create">{link("/tenants/new", "New tenant")}</span> : null}</div>
    {state !== "no-access" ? <label className="navigation-filter"><Search size={16} aria-hidden /><input aria-label="Find a tenant" placeholder="Search by name or tenant key" value={query} onChange={event => onQueryChange(event.target.value)} maxLength={120} /></label> : null}
    {state === "loading" ? <DirectorySkeleton /> : state === "unavailable" ? <div role="alert"><DirectoryEmpty title="Tenants unavailable">We could not load your tenants.</DirectoryEmpty></div> : state === "no-access" ? <DirectoryEmpty title="No tenant access">You do not have access to any tenants. Contact an administrator to request access.</DirectoryEmpty> : !tenants.length ? <DirectoryEmpty title={query ? "No matching tenants" : "No tenants yet"}>{query ? "Try another name or tenant key." : canCreate ? "Create a tenant to get started." : "You do not have access to any tenants. Contact an administrator to request access."}</DirectoryEmpty> : <ul className="navigation-directory">{tenants.map(tenant => <li key={tenant.key}>
      {link(`/t/${tenant.key}/dashboard`, <><span className="navigation-tenant-identity"><strong>{tenant.name}</strong><span className="navigation-tenant-meta"><code>{tenant.key}</code>{tenant.createdAt ? <time dateTime={tenant.createdAt} title={new Date(tenant.createdAt).toLocaleString()}>Created {formatAdminRelativeTime(tenant.createdAt)}</time> : null}</span></span><ArrowRight size={18} aria-hidden /></>, `Open ${tenant.name}`)}
      {tenant.canSetup ? <span className="navigation-tenant-setup">{link(`/t/${tenant.key}/services`, "Setup", `Setup ${tenant.name}`)}</span> : null}
    </li>)}</ul>}
    {state === "ready" ? pagination : null}
  </Container>;
}
export function DirectoryEmpty({ title, children }: { title: string; children: string }) {
  return <div className="navigation-empty"><h2>{title}</h2><p>{children}</p></div>;
}
