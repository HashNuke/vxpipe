import { AdminShell } from "./admin/AdminShell";
import { TenantListSkeleton } from "./admin/TenantListSkeleton";

export function AdminApp({ csrfToken }: { csrfToken: string }) {
  return (
    <AdminShell
      theme="dark"
      headerActions={
        <form action="/auth/logout" method="post">
          <input type="hidden" name="_csrf_token" value={csrfToken} />
          <button
            type="submit"
            className="min-h-9 rounded-md px-3 text-sm font-medium text-[var(--admin-muted)] hover:bg-[var(--admin-soft)] hover:text-[var(--admin-ink)]"
          >
            Sign out
          </button>
        </form>
      }
    >
      <main className="mx-auto w-full max-w-[1600px] px-4 py-8 sm:px-6" aria-busy="true">
        <h1 className="mb-6 text-xl font-bold tracking-[-0.02em]">Tenants</h1>
        <TenantListSkeleton />
      </main>
    </AdminShell>
  );
}
