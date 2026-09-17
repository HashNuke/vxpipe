import { useCallback, useEffect, useState } from "react";

import { parseTenantPage } from "./admin/adminApi";
import { TenantsPage } from "./admin/TenantsPage";
import type { PaginationModel, TenantsPageState } from "./admin/tenantTypes";

type Fetch = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

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
  const [page, setPage] = useState(readPage);
  const [state, setState] = useState<TenantsPageState>({ status: "loading" });

  useEffect(() => {
    const restore = () => setPage(readPage());
    window.addEventListener("popstate", restore);
    return () => window.removeEventListener("popstate", restore);
  }, []);

  useEffect(() => {
    const controller = new AbortController();
    let current = true;
    setState({ status: "loading" });

    void fetchImpl(`/admin/api/tenants?page=${page}`, {
      headers: { accept: "application/json" },
      signal: controller.signal,
    })
      .then(async (response) => {
        if (!current) return;

        if (response.status === 401) {
          onSessionExpired();
          return;
        }

        if (response.status === 422 && page !== 1) {
          window.history.replaceState({}, "", "/admin");
          setPage(1);
          return;
        }

        if (!response.ok) throw new Error("Tenant directory unavailable");

        const result = parseTenantPage(await response.json());
        if (!current) return;

        setState({
          status: "ready",
          tenants: result.tenants,
          pagination: paginationModel(result.pagination),
        });
      })
      .catch((error: unknown) => {
        if (!current || (error instanceof DOMException && error.name === "AbortError")) return;

        setState({
          status: "unavailable",
          message: "Tenant data could not be loaded. Try again after storage is available.",
        });
      });

    return () => {
      current = false;
      controller.abort();
    };
  }, [fetchImpl, onSessionExpired, page]);

  const navigatePage = useCallback((nextPage: number) => {
    const url = nextPage === 1 ? "/admin" : `/admin?page=${nextPage}`;
    window.history.pushState({}, "", url);
    setPage(nextPage);
  }, []);

  return (
    <TenantsPage
      headerActions={<SignOut csrfToken={csrfToken} />}
      onNextPage={() => navigatePage(page + 1)}
      onPreviousPage={() => navigatePage(Math.max(1, page - 1))}
      state={state}
    />
  );
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

function readPage() {
  const raw = new URLSearchParams(window.location.search).get("page");
  if (raw === null) return 1;
  const page = Number(raw);
  return Number.isSafeInteger(page) && page > 0 ? page : 1;
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
