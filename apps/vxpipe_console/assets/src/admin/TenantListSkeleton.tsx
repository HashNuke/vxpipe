export function TenantListSkeleton() {
  return (
    <div
      aria-label="Loading tenants"
      className="animate-pulse motion-reduce:animate-none"
      role="status"
    >
      <span className="sr-only">Loading tenants</span>
      <div className="h-10 border-b border-[var(--admin-line)] bg-[var(--admin-panel)]" />
      {[0, 1, 2, 3].map((row) => (
        <div
          className="grid grid-cols-[1.4fr_1fr_0.55fr] gap-4 border-b border-[var(--admin-line)] px-4 py-5"
          key={row}
        >
          <span className="h-4 w-2/3 bg-[var(--admin-soft)]" />
          <span className="h-4 w-4/5 bg-[var(--admin-soft)]" />
          <span className="h-4 w-1/2 bg-[var(--admin-soft)]" />
        </div>
      ))}
    </div>
  );
}
