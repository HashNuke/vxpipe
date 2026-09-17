export function PageHeader({
  title,
  description,
}: {
  title: string;
  description?: string;
}) {
  return (
    <header className="mb-6 flex flex-col gap-2 border-b border-[var(--admin-line)] pb-5 sm:mb-8 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h1 className="text-xl font-bold tracking-[-0.02em]">{title}</h1>
        {description ? (
          <p className="mt-1 max-w-[68ch] text-sm text-[var(--admin-muted)]">
            {description}
          </p>
        ) : null}
      </div>
    </header>
  );
}
