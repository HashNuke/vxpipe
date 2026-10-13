import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Link, Outlet, useLocation, useNavigate, useParams } from "react-router";
import { AdminLayoutContext } from "../AdminLayoutContext";
import { AuthenticationApi, isSessionExpired } from "../authentication/authenticationApi";
import { Button } from "../Button";
import { NavigationShell } from "./NavigationShell";
import { TenantPicker } from "./TenantPicker";
import { NavigationApi, NavigationError, type NavigationData, type NavigationFetch , type NavigationTenant } from "./navigationApi";
import { NavigationContext, tenantItems, projectionAllowsPath } from "./navigationContext";
import { useTenantSearch } from "./useTenantSearch";

const expire = () => window.location.assign("/auth/login");
export function ConsoleNavigation({ csrfToken, fetchImpl, onSessionExpired = expire, children, external = false, crossDocument = external }: {
  csrfToken: string; fetchImpl?: NavigationFetch; onSessionExpired?: () => void; children?: ReactNode; external?: boolean; crossDocument?: boolean;
}) {
  const api = useMemo(() => new NavigationApi(fetchImpl, csrfToken), [fetchImpl, csrfToken]);
  const auth = useMemo(() => new AuthenticationApi(csrfToken, fetchImpl), [csrfToken, fetchImpl]);
  const location = useLocation();
  const navigate = useNavigate();
  const go = (path: string) => { if (crossDocument) window.location.assign(path); else void navigate(path); };
  const { tenantKey } = useParams();
  const [selection, setSelection] = useState<string>();
  const selectedKey = tenantKey ?? selection;
  const [result, setResult] = useState<{ key?: string; data: NavigationData }>();
  const [unavailable, setUnavailable] = useState(false);
  const [revision, setRevision] = useState(0);
  const [session, setSession] = useState<Awaited<ReturnType<AuthenticationApi["session"]>>>();
  const expired = useRef(false);
  const [sessionUnavailable, setSessionUnavailable] = useState(false);
  const [logoutError, setLogoutError] = useState(false);
  const refresh = useCallback(() => setRevision(value => value + 1), []);
  const fail = useCallback((error: unknown) => {
    if (error instanceof NavigationError && error.status === 401) { setResult(undefined); setSelection(undefined); setSession(undefined); if (!expired.current) { expired.current = true; onSessionExpired(); } }
    else if (error instanceof NavigationError && (error.status === 403 || error.status === 404)) { setResult(undefined); setSelection(undefined); refresh(); }
  }, [onSessionExpired, refresh]);
  useEffect(() => {
    const controller = new AbortController();
    setUnavailable(false);
    api.navigation(selectedKey, controller.signal).then(data => {
      if (controller.signal.aborted || expired.current) return;
      setResult({ key: selectedKey, data });
      if (tenantKey) setSelection(tenantKey);
      if (location.pathname === "/" || location.pathname === "/admin") navigate(data.landingPath, { replace: true });
      else if (["/tenants", "/my-tenants"].includes(location.pathname) && location.pathname !== data.directoryPath) navigate(data.directoryPath, { replace: true });
    }).catch(async error => {
      if (controller.signal.aborted) return;
      setResult(undefined);
      if (error instanceof NavigationError && error.status === 404 && selectedKey) {
        setSelection(undefined);
        try {
          const data = await api.navigation(undefined, controller.signal);
          if (!controller.signal.aborted) { setResult({ data }); navigate(data.landingPath, { replace: true }); }
        } catch (nextError) { if (!controller.signal.aborted) { fail(nextError); setUnavailable(true); } }
      } else { fail(error); setUnavailable(true); }
    });
    return () => controller.abort();
  }, [api, selectedKey, tenantKey, location.pathname, revision, navigate, fail]);
  useEffect(() => {
    let active = true;
    setSessionUnavailable(false);
    auth.session().then(session => {
      if (!session?.user?.id || typeof session.user.email !== "string" || !Array.isArray(session.user.memberships) || !Array.isArray(session.role?.grants)) throw new Error("Invalid session response");
      if (active && !expired.current) setSession(session);
    }).catch(error => {
      if (!active) return;
      setSession(undefined); setSessionUnavailable(true);
      if (isSessionExpired(error)) fail(new NavigationError(401));
    });
    return () => { active = false; };
  }, [auth, revision, fail]);
  useEffect(() => { window.addEventListener("focus", refresh); return () => window.removeEventListener("focus", refresh); }, [refresh]);
  const data = result?.key === selectedKey ? result?.data : undefined;
  const tenant = data?.tenant;
  return <NavigationShell external={external} tenants={[]} selected={tenant ? { ...tenant, id: tenant.key } : undefined} email={session?.user.email}
    projectedItems={{ tenant: tenantItems(tenant ?? null), platform: data?.platform ?? [] }} path={location.pathname}
    realLinks onNavigate={go} onLogout={() => {
      setLogoutError(false);
      void auth.logout().then(() => { setResult(undefined); setSelection(undefined); setSession(undefined); if (!expired.current) { expired.current = true; onSessionExpired(); } }).catch(() => setLogoutError(true));
    }} theme="dark" onRetry={refresh}
    picker={data ? <ServerTenantPicker key={data.actor.id} api={api} data={data} onNavigate={go} onFailure={fail} /> : undefined}>
    {logoutError ? <p role="alert">Logout failed. Try again.</p> : null}
    {data ? <NavigationContext value={{ api, data, session, sessionUnavailable, refresh, fail }}><AdminLayoutContext value>{projectionAllowsPath(data, location.pathname) ? children ?? <Outlet /> : <main><h1>Access unavailable</h1><p>Your current role does not allow this page.</p><Button onClick={refresh}>Try again</Button></main>}</AdminLayoutContext></NavigationContext>
      : unavailable ? <main role="alert"><h1>Navigation unavailable</h1><p>Your workspace could not be loaded.</p><Button onClick={refresh}>Try again</Button></main>
        : <p role="status">Loading workspace…</p>}
  </NavigationShell>;
}

function ServerTenantPicker({ api, data, onNavigate, onFailure }: {
  api: NavigationApi; data: NavigationData; onNavigate: (path: string) => void; onFailure: (error: unknown) => void;
}) {
  const [open, setOpen] = useState(false);
  const search = useTenantSearch(api, data.directoryAccess && open, onFailure, data);
  return <TenantPicker onOpenChange={setOpen} realLinks tenants={search.tenants.map(tenant => ({ ...tenant, id: tenant.key }))}
    selected={data.tenant ? { ...data.tenant, id: data.tenant.key } : undefined} directoryPath={data.directoryPath}
    onNavigate={onNavigate} state={search.state} onRetry={search.retry} query={search.query} onQueryChange={search.setQuery}
    onMore={search.hasMore ? search.more : undefined} />;
}
export function TenantContextLine({ tenant }: { tenant: NavigationTenant }) {
  return <div className="navigation-context"><Link to={tenant.dashboardPath}>{tenant.name}</Link><code>{tenant.key}</code></div>;
}
