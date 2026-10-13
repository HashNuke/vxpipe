import { useEffect, useState } from "react";
import type { TenantSummary } from "../tenantTypes";
import type { NavigationApi } from "./navigationApi";

/** Requests only authorized server pages; abort and generation checks protect every update. */
export function useTenantSearch(api: NavigationApi, enabled: boolean, onFailure: (error: unknown) => void, authority?: unknown) {
  const [query, updateQuery] = useState("");
  const [page, setPage] = useState(1);
  const [revision, setRevision] = useState(0);
  const [tenants, setTenants] = useState<TenantSummary[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [state, setState] = useState<"ready" | "loading" | "unavailable">("loading");
  useEffect(() => { setPage(1); setTenants([]); setHasMore(false); }, [authority]);
  useEffect(() => {
    const controller = new AbortController();
    if (!enabled) { setPage(1); setTenants([]); setHasMore(false); setState("ready"); return () => controller.abort(); }
    setState("loading");
    const timer = window.setTimeout(() => {
      api.tenants(query, page, controller.signal).then(result => {
        if (controller.signal.aborted) return;
        setTenants(current => page === 1 ? result.tenants : [...current, ...result.tenants.filter(item => !current.some(existing => existing.key === item.key))]);
        setHasMore(result.pagination.page < result.pagination.totalPages);
        setState("ready");
      }).catch(error => {
        if (controller.signal.aborted) return;
        setTenants([]); setHasMore(false); setState("unavailable"); onFailure(error);
      });
    }, query ? 200 : 0);
    return () => { window.clearTimeout(timer); controller.abort(); };
  }, [api, enabled, query, page, revision, onFailure, authority]);
  return { query, tenants, hasMore, state,
    setQuery: (value: string) => { updateQuery(value); setPage(1); setTenants([]); setHasMore(false); },
    more: () => setPage(value => value + 1), retry: () => { setPage(1); setRevision(value => value + 1); },
  };
}
