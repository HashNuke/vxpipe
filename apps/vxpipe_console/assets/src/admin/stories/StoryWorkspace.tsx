import { useState, type ReactNode } from "react";
import { AdminLayoutContext } from "../AdminLayoutContext";
import type { TenantApiKey } from "../tenantApiKeys";
import { NavigationJourney } from "../navigation/NavigationJourney";
import { NavigationShell } from "../navigation/NavigationShell";
import { navigationFixture } from "../navigation/navigationFixtures";
import { visibleTenants } from "../navigation/navigationPolicy";
import { tenants as defaultTenants } from "../authentication/fixtures";
import type { Role, Tenant, Theme, User } from "../authentication/types";

/** Compose fixture page states with the same shell used by the Console. */
export function StoryWorkspace({ children, path, tenant, theme = "dark", user, role, initialTenantKeys, onNavigate, onWorkspaceNavigate, onLogout, tenantOptions = defaultTenants }: {
  children: ReactNode | ((navigate: (path: string) => void) => ReactNode);
  tenantOptions?: Tenant[]; path: string; tenant?: { key: string; name: string }; theme?: Theme;
  initialTenantKeys?: Record<string, TenantApiKey[]>;
  onWorkspaceNavigate?: (path: string) => boolean; user?: User; role?: Role; onNavigate?: (path: string) => void; onLogout?: () => void;
}) {
  const [destination, setDestination] = useState<string>();
  const fixture = navigationFixture("all");
  const actor = user ?? fixture.user;
  const authority = role ?? fixture.role;
  const tenants: Tenant[] = tenant && !tenantOptions.some(item => item.key === tenant.key)
    ? [{ ...tenant, id: tenant.key }, ...tenantOptions] : tenantOptions;
  const navigate = (next: string) => {
    if (onWorkspaceNavigate?.(next)) return;
    if (onNavigate && (/^\/(users|roles|account)(\/|$)/.test(next) || next === "/platform/installation")) onNavigate(next);
    else setDestination(next);
  };
  if (destination) return <NavigationJourney key={destination} initialPath={destination} initialTenantKeys={initialTenantKeys} initialTenants={tenants} identity={{ user: actor, role: authority }} theme={theme} />;
  return <NavigationShell theme={theme} path={path} user={actor} role={authority}
    tenants={visibleTenants(authority, actor, tenants)} selected={tenant ? { ...tenant, id: tenant.key } : undefined}
    onNavigate={navigate} onLogout={onLogout ?? (() => setDestination("/auth/login"))} onRetry={() => undefined}>
    <AdminLayoutContext value>{typeof children === "function" ? children(navigate) : children}</AdminLayoutContext>
  </NavigationShell>;
}
