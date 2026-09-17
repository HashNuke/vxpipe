export function CallDetailsSkeleton() {
  return (
    <section
      aria-label="Loading call details"
      className="animate-pulse border border-[var(--admin-line)] bg-[var(--admin-panel)] p-5 motion-reduce:animate-none"
      role="status"
    >
      <span className="sr-only">Loading call details</span>
      <div className="h-16 bg-[var(--admin-soft)]" />
      <div className="mt-4 grid min-h-96 grid-cols-[180px_1fr] gap-4">
        <div className="bg-[var(--admin-soft)]" />
        <div className="bg-[var(--admin-soft)]" />
      </div>
    </section>
  );
}
