import { useEffect, useState } from "react";

import { parseDefinitionPage, parseTenantPage } from "./admin/adminApi";
import { TenantDefinitionsPage } from "./admin/TenantDefinitionsPage";
import type { TenantDefinitionsPageState } from "./admin/definitionTypes";
import { TenantsPage } from "./admin/TenantsPage";
import type { PaginationModel, TenantsPageState } from "./admin/tenantTypes";

type Fetch = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

type AdminRoute =
  | { kind: "tenants"; page: number }
  | { kind: "definitions"; tenantKey: string; page: number };

const defaultFetch: Fetch = (input, init) => window.fetch(input, init);
const redirectExpiredSession = () => window.location.assign("/auth/login");

export function AdminApp({
  csrfToken,
  fetchImpl = defaultFetch,
  onSessionExpired = redirectExpiredSession,
}: {
  csrfToken: string;
  fetchImpl?: Fetch;
  onSessionExpired?: () => void;
}) {
  const [route, setRoute] = useState(readRoute);
  const [tenants, setTenants] = useState<TenantsPageState>({ status: "loading" });
  const [definitions, setDefinitions] = useState<TenantDefinitionsPageState>(() => ({
    status: "loading",
    tenant:
      route.kind === "definitions" ? tenantPlaceholder(route.tenantKey) : tenantPlaceholder(""),
  }));

  useEffect(() => {
    const restore = () => setRoute(readRoute());
    window.addEventListener("popstate", restore);
    return () => window.removeEventListener("popstate", restore);
  }, []);

  useEffect(() => {
    const controller = new AbortController();
    let current = true;
    const isCurrent = () => current;

    if (route.kind === "tenants") {
      setTenants({ status: "loading" });
      loadTenants(
        route,
        controller.signal,
        fetchImpl,
        onSessionExpired,
        isCurrent,
        () => {
          const firstPage = { kind: "tenants", page: 1 } as const;
          window.history.replaceState({}, "", routeUrl(firstPage));
          setRoute(firstPage);
        },
      )
        .then((state) => {
          if (current && state) setTenants(state);
        })
        .catch((error: unknown) => {
          if (current && !aborted(error)) {
            setTenants({
              status: "unavailable",
              message: "Tenant data could not be loaded. Try again after storage is available.",
            });
          }
        });
    } else {
      setDefinitions((state) => ({
        status: "loading",
        tenant:
          state.tenant.key === route.tenantKey
            ? state.tenant
            : tenantPlaceholder(route.tenantKey),
      }));

      loadDefinitions(
        route,
        controller.signal,
        fetchImpl,
        onSessionExpired,
        isCurrent,
        () => {
          const firstPage = { ...route, page: 1 };
          window.history.replaceState({}, "", routeUrl(firstPage));
          setRoute(firstPage);
        },
      )
        .then((state) => {
          if (current && state) setDefinitions(state);
        })
        .catch((error: unknown) => {
          if (current && !aborted(error)) {
            setDefinitions((state) => ({
              status: "unavailable",
              tenant: state.tenant,
              message:
                "Call definitions could not be loaded. Try again after storage is available.",
            }));
          }
        });
    }

    return () => {
      current = false;
      controller.abort();
    };
  }, [fetchImpl, onSessionExpired, route]);

  function navigate(nextRoute: AdminRoute, replace = false) {
    window.history[replace ? "replaceState" : "pushState"]({}, "", routeUrl(nextRoute));
    setRoute(nextRoute);
  }

  const headerActions = <SignOut csrfToken={csrfToken} />;

  if (route.kind === "definitions") {
    return (
      <TenantDefinitionsPage
        headerActions={headerActions}
        linkCalls={false}
        onNextPage={() => navigate({ ...route, page: route.page + 1 })}
        onPreviousPage={() => navigate({ ...route, page: Math.max(1, route.page - 1) })}
        onSelectTenants={() => navigate({ kind: "tenants", page: 1 })}
        state={definitions}
        workspaceDestinations={["definitions"]}
      />
    );
  }

  return (
    <TenantsPage
      headerActions={headerActions}
      onNextPage={() => navigate({ kind: "tenants", page: route.page + 1 })}
      onPreviousPage={() => navigate({ kind: "tenants", page: Math.max(1, route.page - 1) })}
      onSelectTenant={(tenantKey) => navigate({ kind: "definitions", tenantKey, page: 1 })}
      state={tenants}
    />
  );
}

async function loadTenants(
  selected: Extract<AdminRoute, { kind: "tenants" }>,
  signal: AbortSignal,
  fetchImpl: Fetch,
  onSessionExpired: () => void,
  isCurrent: () => boolean,
  recoverFirstPage: () => void,
): Promise<TenantsPageState | undefined> {
  const response = await fetchImpl(`/admin/api/tenants?page=${selected.page}`, {
    headers: { accept: "application/json" },
    signal,
  });

  if (!isCurrent()) return;

  if (response.status === 401) {
    onSessionExpired();
    return;
  }

  if (response.status === 422 && selected.page !== 1) {
    recoverFirstPage();
    return;
  }

  if (!response.ok) throw new Error("Tenant directory unavailable");
  const result = parseTenantPage(await response.json());
  if (!isCurrent()) return;

  return {
    status: "ready",
    tenants: result.tenants,
    pagination: paginationModel(result.pagination),
  };
}

async function loadDefinitions(
  selected: Extract<AdminRoute, { kind: "definitions" }>,
  signal: AbortSignal,
  fetchImpl: Fetch,
  onSessionExpired: () => void,
  isCurrent: () => boolean,
  recoverFirstPage: () => void,
): Promise<TenantDefinitionsPageState | undefined> {
  const encodedTenant = encodeURIComponent(selected.tenantKey);
  const response = await fetchImpl(
    `/admin/api/tenants/${encodedTenant}/definitions?page=${selected.page}`,
    { headers: { accept: "application/json" }, signal },
  );

  if (!isCurrent()) return;

  if (response.status === 401) {
    onSessionExpired();
    return;
  }

  if (response.status === 422 && selected.page !== 1) {
    recoverFirstPage();
    return;
  }

  if (response.status === 404) {
    return {
      status: "unavailable",
      tenant: tenantPlaceholder(selected.tenantKey),
      message: "This tenant could not be found.",
    };
  }

  if (!response.ok) throw new Error("Definition directory unavailable");
  const result = parseDefinitionPage(await response.json());
  if (!isCurrent()) return;
  if (result.tenant.key !== selected.tenantKey) throw new Error("Unexpected tenant response");

  return {
    status: "ready",
    tenant: result.tenant,
    definitions: result.definitions,
    pagination: paginationModel(result.pagination),
  };
}

function SignOut({ csrfToken }: { csrfToken: string }) {
  return (
    <form action="/auth/logout" method="post">
      <input type="hidden" name="_csrf_token" value={csrfToken} />
      <button
        type="submit"
        className="min-h-9 rounded-md px-3 text-sm font-medium text-[var(--admin-muted)] hover:bg-[var(--admin-soft)] hover:text-[var(--admin-ink)]"
      >
        Sign out
      </button>
    </form>
  );
}

function readRoute(): AdminRoute {
  const page = readPage();
  const match = window.location.pathname.match(
    /^\/admin\/tenants\/([^/]+)(\/definitions)?\/?$/,
  );

  if (!match) return { kind: "tenants", page };

  try {
    const tenantKey = decodeURIComponent(match[1]);
    const route = { kind: "definitions", tenantKey, page } as const;
    if (!match[2]) window.history.replaceState({}, "", routeUrl(route));
    return route;
  } catch {
    return { kind: "tenants", page: 1 };
  }
}

function routeUrl(route: AdminRoute) {
  const query = route.page === 1 ? "" : `?page=${route.page}`;
  if (route.kind === "tenants") return `/admin${query}`;
  return `/admin/tenants/${encodeURIComponent(route.tenantKey)}/definitions${query}`;
}

function readPage() {
  const raw = new URLSearchParams(window.location.search).get("page");
  if (raw === null) return 1;
  const page = Number(raw);
  return Number.isSafeInteger(page) && page > 0 ? page : 1;
}

function tenantPlaceholder(key: string) {
  return { key, name: key || "Tenant" };
}

function aborted(error: unknown) {
  return error instanceof DOMException && error.name === "AbortError";
}

function paginationModel({
  page,
  pageSize,
  total,
  totalPages,
}: {
  page: number;
  pageSize: number;
  total: number;
  totalPages: number;
}): PaginationModel | null {
  if (totalPages <= 1) return null;

  const first = (page - 1) * pageSize + 1;
  const last = Math.min(page * pageSize, total);

  return {
    label: `${first}–${last} of ${total}`,
    hasPrevious: page > 1,
    hasNext: page < totalPages,
  };
}
