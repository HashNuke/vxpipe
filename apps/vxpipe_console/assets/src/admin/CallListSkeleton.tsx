export function CallListSkeleton() {
  return (
    <div
      aria-label="Loading calls"
      className="animate-pulse motion-reduce:animate-none"
      role="status"
    >
      <span className="sr-only">Loading calls</span>
      <div className="h-10 border-b border-[var(--admin-line)] bg-[var(--admin-panel)]" />
      {[0, 1, 2, 3].map((row) => (
        <div
          className="grid grid-cols-[1.4fr_120px_120px] gap-4 border-b border-[var(--admin-line)] px-4 py-5"
          key={row}
        >
          <span className="h-4 w-2/3 bg-[var(--admin-soft)]" />
          <span className="h-4 w-20 bg-[var(--admin-soft)]" />
          <span className="h-4 w-20 bg-[var(--admin-soft)]" />
        </div>
      ))}
    </div>
  );
}
