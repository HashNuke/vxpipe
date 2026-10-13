import { useEffect, useState } from "react";
import { Link, useParams } from "react-router";
import { ArrowRight, Search } from "lucide-react";
import { Button } from "../Button";
import { RecentCalls } from "./RecentCalls";
import { TenantContextLine } from "./ConsoleNavigation";
import { tenantItems, useConsoleNavigation } from "./navigationContext";
import type { DashboardData } from "./navigationApi";
import { useTenantDirectory } from "./useTenantDirectory";
import { Pagination } from "../Pagination";
import { canCreateTenants } from "../authentication/access";

export function WorkspaceDirectory() {
  const { data, session } = useConsoleNavigation();
  const search = useTenantDirectory();
  const tenants = search.result?.tenants ?? [];
  return <main><div className="navigation-heading"><div><h1>{data.scope === "all" ? "Tenants" : "My tenants"}</h1><p>Choose a tenant to open its workspace.</p></div>{session && canCreateTenants(session.role) ? <Link to="/getting-started">Getting started</Link> : null}</div>
    {!data.directoryAccess ? <Empty title="No tenant access">You do not have access to a tenant yet. Contact an administrator to request access.</Empty> : <>
      <label className="navigation-filter"><Search size={16} aria-hidden /><input aria-label="Find a tenant" placeholder="Search by name or tenant key" value={search.query} onChange={event => search.setQuery(event.target.value)} maxLength={120} /></label>
      {search.state === "loading" ? <p role="status">Loading tenants…</p> : search.state === "unavailable" ? <div role="alert"><Empty title="Tenants unavailable">Your tenants could not be loaded.</Empty><Button onClick={search.retry}>Try again</Button></div> : <>
        {!tenants.length ? <Empty title={search.query ? "No matching tenants" : "No tenants available"}>{search.query ? "Try another name or tenant key." : "No tenant workspaces are available to your account."}</Empty>
          : <ul className="navigation-directory">{tenants.map(tenant => <li key={tenant.key}><Link aria-label={`Open ${tenant.name}`} to={`/t/${tenant.key}/dashboard`}><span><strong>{tenant.name}</strong><code>{tenant.key}</code></span><ArrowRight size={18} aria-hidden /></Link></li>)}</ul>}
        {search.result && search.result.pagination.totalPages > 1 ? <Pagination ariaLabel="Tenant pages" pagination={{ label: `Page ${search.page} of ${search.result.pagination.totalPages}`, hasPrevious: search.page > 1, hasNext: search.page < search.result.pagination.totalPages }} onPrevious={() => search.setPage(search.page - 1)} onNext={() => search.setPage(search.page + 1)} /> : null}
      </>}
    </>}
  </main>;
}
export function WorkspaceDashboard() {
  const { tenantKey = "" } = useParams();
  const { api, data, fail } = useConsoleNavigation();
  const [result, setResult] = useState<DashboardData>();
  const [unavailable, setUnavailable] = useState(false);
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    const controller = new AbortController();
    setResult(undefined); setUnavailable(false);
    api.dashboard(tenantKey, controller.signal).then(value => {
      if (!controller.signal.aborted) setResult(value);
    }).catch(error => { if (!controller.signal.aborted) { setUnavailable(true); fail(error); } });
    return () => controller.abort();
  }, [api, data, tenantKey, revision, fail]);
  const current = result?.tenant.key === tenantKey ? result : undefined;
  const tenant = current?.tenant ?? data.tenant;
  return <main>{tenant ? <TenantContextLine tenant={tenant} /> : null}<div className="navigation-heading"><div><h1>Dashboard</h1><p>Your tenant workspace.</p></div></div>
    <div className="navigation-shortcuts">{tenantItems(tenant).map(item => <Link key={item.href} to={item.href}>{item.label}<ArrowRight size={16} aria-hidden /></Link>)}</div>
    {unavailable ? <div role="alert"><Empty title="Dashboard unavailable">Your workspace could not be loaded.</Empty><Button onClick={() => setRevision(value => value + 1)}>Try again</Button></div>
      : !current ? <p role="status">Loading dashboard…</p> : data.tenant?.capabilities.calls.read && current.recentCalls ? <section aria-label="Recent calls"><div className="navigation-section-title"><h2>Recent calls</h2><Link to={`/t/${tenantKey}/calls`}>View all calls</Link></div>
        {current.recentCalls.status === "unavailable" ? <div role="alert"><Empty title="Recent calls unavailable">The call directory could not be loaded. Your other workspace tools are available.</Empty><Button onClick={() => setRevision(value => value + 1)}>Try again</Button></div>
          : current.recentCalls.calls.length ? <RecentCalls calls={current.recentCalls.calls} callHref={id => `/admin/tenants/${tenantKey}/calls/${encodeURIComponent(id)}`} />
            : <Empty title="No calls yet">Calls will appear here when this tenant starts receiving traffic.</Empty>}
      </section> : null}
  </main>;
}
function Empty({ title, children }: { title: string; children: string }) {
  return <div className="navigation-empty"><h2>{title}</h2><p>{children}</p></div>;
}
