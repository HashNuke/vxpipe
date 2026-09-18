import { Breadcrumbs, type BreadcrumbItem } from "./Breadcrumbs";

export function CallDetailsConsoleHeader({
  breadcrumbs,
}: {
  breadcrumbs: BreadcrumbItem[];
}) {
  return (
    <div className="flex min-h-9 min-w-0 items-center gap-3 sm:gap-6">
      <span className="shrink-0 font-sans text-base font-bold tracking-[-0.03em] text-[var(--admin-ink)]">Vxpipe</span>
      <Breadcrumbs compact items={breadcrumbs} />
    </div>
  );
}
