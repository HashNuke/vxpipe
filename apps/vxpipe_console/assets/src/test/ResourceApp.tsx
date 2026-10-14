import { useMemo, type ComponentProps } from "react";
import { App as ProductionApp } from "../App";
import { effectiveAccess, membershipAccess } from "../admin/authentication/access";
import type { Role, User } from "../admin/authentication/types";
import { allTenants, navigationItems } from "../admin/navigation/navigationPolicy";

/** Existing resource tests supply session/resource fixtures. Add the separate navigation
 * boundary's equivalent fixture; App.navigation tests exercise the real wire contract. */
export function App(props: ComponentProps<typeof ProductionApp>) {
  const fetchImpl = useMemo(() => {
    const { promise: session, resolve: resolveSession, reject: rejectSession } = deferredSession();
    // Some standalone routes never request navigation.
    void session.catch(() => {});
    return async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = new URL(String(input), "http://localhost");
      if (url.pathname === "/admin/api/navigation") {
        try {
          const { user, role } = await session;
          const key = url.searchParams.get("tenant");
          const capability = (resource: string) => {
            const access = effectiveAccess(role, resource, key ? membershipAccess(user, key) : undefined);
            return { read: access !== "none", write: access === "write" };
          };
          const directory = "/tenants";
          const tenant = key ? { key, name: key.startsWith("acme") ? "Acme" : "Example tenant", dashboard_path: `/t/${key}/dashboard`, capabilities: { calls: capability("calls"), call_specs: capability("call_specs"), services: capability("tenant_services"), api_keys: capability("tenant_api_keys") } } : null;
          const destinations = navigationItems(role, user).platform.map(item => ({ id: item.label === "API Keys" ? "api_keys" : item.label.toLowerCase(), label: item.label, path: item.href }));
          return Response.json({ actor: { id: user.id, kind: role.kind ?? "member" }, tenant_scope: allTenants(role) ? "all" : "assigned", directory_access: !!role.kind || role.grants.some(grant => ["calls.read", "call_specs.read", "tenant_services.read", "tenants.read"].includes(grant.permission)), directory_path: directory, landing_path: directory, platform_destinations: destinations, tenant });
        } catch { return Response.json({}, { status: 503 }); }
      }
      let response: Response;
      try { response = await props.fetchImpl!(input, init); } catch (error) { if (url.pathname === "/admin/api/session") rejectSession!(error); throw error; }
      if (url.pathname === "/admin/api/session") {
        if (response.ok) resolveSession!((await response.clone().json()) as { user: User; role: Role });
        else rejectSession!(new Error("No session"));
      }
      return response;
    };
  }, [props.fetchImpl]);
  return <ProductionApp {...props} fetchImpl={fetchImpl} />;
}

function deferredSession() {
  let resolve!: (value: { user: User; role: Role }) => void;
  let reject!: (error: unknown) => void;
  const promise = new Promise<{ user: User; role: Role }>((done, fail) => { resolve = done; reject = fail; });
  return { promise, resolve, reject };
}
