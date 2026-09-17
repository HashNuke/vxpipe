import { Breadcrumbs, type BreadcrumbItem } from "./Breadcrumbs";

export function CallDetailsConsoleHeader({
  breadcrumbs,
}: {
  breadcrumbs: BreadcrumbItem[];
}) {
  return (
    <div className="min-w-0">
      <Breadcrumbs compact items={breadcrumbs} />
    </div>
  );
}
