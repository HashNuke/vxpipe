import { createContext, useContext } from "react";
import { NavigationApi, type NavigationData, type NavigationTenant } from "./navigationApi";
import type { Role, User } from "../authentication/types";
import type { NavigationItem } from "./navigationPolicy";

export const NavigationContext = createContext<{
  sessionUnavailable: boolean; session?: { user: User; role: Role }; api: NavigationApi; data: NavigationData; refresh: () => void; fail: (error: unknown) => void;
} | null>(null);
export function useConsoleNavigation() {
  const context = useContext(NavigationContext);
  if (!context) throw new Error("Console navigation is unavailable");
  return context;
}
export function tenantItems(tenant: NavigationTenant | null): NavigationItem[] {
  if (!tenant) return [];
  const caps = tenant.capabilities;
  return [
    ...(caps.calls.read ? [{ label: "Calls", href: `/t/${tenant.key}/calls` }] : []),
    ...(caps.call_specs.read ? [{ label: "Call Specs", href: `/t/${tenant.key}/call-specs` }] : []),
    ...(caps.services.read || caps.api_keys.read ? [{ label: "Services", href: `/t/${tenant.key}/services` }] : []),
  ];
}

export function projectionAllowsPath(data: NavigationData, pathname: string): boolean {
  const path = pathname.replace(/\/+$/, "");
  if (path.startsWith("/t/")) return path === data.tenant?.dashboardPath || tenantItems(data.tenant).some(item => item.href === path);
  if (/^\/(api-keys|users|roles)(\/|$)/.test(path) || path === "/platform/services") return data.platform.some(item => path === item.href || path.startsWith(`${item.href}/`));
  return true;
}
