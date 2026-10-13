import { useEffect, useState } from "react";
import { useSearchParams } from "react-router";
import type { TenantDirectoryPage } from "../adminApi";
import { NavigationError } from "./navigationApi";
import { useConsoleNavigation } from "./navigationContext";

export function useTenantDirectory() {
  const { api, data, fail } = useConsoleNavigation();
  const [params, setParams] = useSearchParams();
  const query = params.get("q") ?? "";
  const rawPage = Number(params.get("page") ?? "1");
  const page = Number.isSafeInteger(rawPage) && rawPage > 0 ? rawPage : 1;
  const [result, setResult] = useState<TenantDirectoryPage>();
  const [state, setState] = useState<"loading" | "ready" | "unavailable">("loading");
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    const controller = new AbortController();
    setResult(undefined);
    if (!data.directoryAccess) { setState("ready"); return () => controller.abort(); }
    setState("loading");
    const timer = window.setTimeout(() => {
      api.tenants(query, page, controller.signal).then(value => {
        if (!controller.signal.aborted) { setResult(value); setState("ready"); }
      }).catch(error => {
        if (controller.signal.aborted) return;
        if (error instanceof NavigationError && error.status === 422 && page > 1) {
          const next = new URLSearchParams(params); next.delete("page"); setParams(next, { replace: true });
        } else { setState("unavailable"); fail(error); }
      });
    }, query ? 200 : 0);
    return () => { controller.abort(); window.clearTimeout(timer); };
  }, [api, data, query, page, params, setParams, revision, fail]);
  return { result, state, query, page,
    retry: () => setRevision(value => value + 1),
    setQuery: (value: string) => { const next = new URLSearchParams(params); next.delete("page"); if (value) next.set("q", value); else next.delete("q"); setParams(next, { replace: true }); },
    setPage: (value: number) => { const next = new URLSearchParams(params); if (value > 1) next.set("page", String(value)); else next.delete("page"); setParams(next); },
  };
}
