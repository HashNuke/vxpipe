export function CallSpecListSkeleton() {
  return (
    <div
      aria-label="Loading call specs"
      className="animate-pulse motion-reduce:animate-none"
      role="status"
    >
      <span className="sr-only">Loading call specs</span>
      <div className="h-10 border-b border-[var(--admin-line)] bg-[var(--admin-panel)]" />
      {[0, 1, 2, 3].map((row) => (
        <div
          className="grid grid-cols-[1.2fr_1fr_90px_130px] gap-4 border-b border-[var(--admin-line)] px-4 py-5"
          key={row}
        >
          <span className="h-4 w-2/3 bg-[var(--admin-soft)]" />
          <span className="h-4 w-4/5 bg-[var(--admin-soft)]" />
          <span className="h-4 w-8 bg-[var(--admin-soft)]" />
          <span className="h-4 w-20 bg-[var(--admin-soft)]" />
        </div>
      ))}
    </div>
  );
}
