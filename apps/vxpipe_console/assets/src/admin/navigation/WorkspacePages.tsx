import { useEffect, useState } from "react";
import { Link, useParams } from "react-router";
import { DirectoryEmpty as Empty, DirectorySkeleton, TenantDirectoryView } from "./TenantDirectoryView";
import { RecentCalls } from "./RecentCalls";
import { TenantContextLine } from "./ConsoleNavigation";
import { useConsoleNavigation } from "./navigationContext";
import type { DashboardData } from "./navigationApi";
import { useTenantDirectory } from "./useTenantDirectory";
import { Pagination } from "../Pagination";
import { canCreateTenants } from "../authentication/access";

export function WorkspaceDirectory() {
  const { data, session } = useConsoleNavigation();
  const search = useTenantDirectory();
  const tenants = search.result?.tenants ?? [];
  return <TenantDirectoryView title={data.scope === "all" ? "Tenants" : "My tenants"}
    state={!data.directoryAccess ? "no-access" : search.state} tenants={tenants}
    query={search.query} onQueryChange={search.setQuery} canCreate={!!session && canCreateTenants(session.role)}
    link={(href, children, label) => <Link to={href} aria-label={label}>{children}</Link>}
    pagination={search.result && search.result.pagination.totalPages > 1 ? <Pagination ariaLabel="Tenant pages" pagination={{ label: `Page ${search.page} of ${search.result.pagination.totalPages}`, hasPrevious: search.page > 1, hasNext: search.page < search.result.pagination.totalPages }} onPrevious={() => search.setPage(search.page - 1)} onNext={() => search.setPage(search.page + 1)} /> : null}
  />;
}
export function WorkspaceDashboard() {
  const { tenantKey = "" } = useParams();
  const { api, data, fail } = useConsoleNavigation();
  const [result, setResult] = useState<DashboardData>();
  const [unavailable, setUnavailable] = useState(false);
  useEffect(() => {
    const controller = new AbortController();
    setResult(undefined); setUnavailable(false);
    api.dashboard(tenantKey, controller.signal).then(value => {
      if (!controller.signal.aborted) setResult(value);
    }).catch(error => { if (!controller.signal.aborted) { setUnavailable(true); fail(error); } });
    return () => controller.abort();
  }, [api, data, tenantKey, fail]);
  const current = result?.tenant.key === tenantKey ? result : undefined;
  const tenant = current?.tenant ?? data.tenant;
  return <main>{tenant ? <TenantContextLine tenant={tenant} /> : null}<div className="navigation-heading"><div><h1>Dashboard</h1><p>Your tenant workspace.</p></div></div>
    {unavailable ? <div role="alert"><Empty title="Dashboard unavailable">Your workspace could not be loaded.</Empty></div>
      : !current ? <DirectorySkeleton label="Loading dashboard" /> : data.tenant?.capabilities.calls.read && current.recentCalls ? <section aria-label="Recent calls"><div className="navigation-section-title"><h2>Recent calls</h2><Link to={`/t/${tenantKey}/calls`}>View all calls</Link></div>
        {current.recentCalls.status === "unavailable" ? <div role="alert"><Empty title="Recent calls unavailable">The call directory could not be loaded. Your other workspace tools are available.</Empty></div>
          : current.recentCalls.calls.length ? <RecentCalls calls={current.recentCalls.calls} callHref={id => `/admin/tenants/${tenantKey}/calls/${encodeURIComponent(id)}`} />
            : <Empty title="No calls yet">Calls will appear here when this tenant starts receiving traffic.</Empty>}
      </section> : null}
  </main>;
}
