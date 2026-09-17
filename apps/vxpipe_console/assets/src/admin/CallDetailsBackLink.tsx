import { ArrowLeft } from "lucide-react";
import type { MouseEvent } from "react";

import type { BreadcrumbItem } from "./Breadcrumbs";
import { shouldInterceptNavigation } from "./shouldInterceptNavigation";

export function CallDetailsBackLink({ item }: { item: BreadcrumbItem }) {
  function handleClick(event: MouseEvent<HTMLAnchorElement>) {
    if (!item.onSelect || !shouldInterceptNavigation(event)) return;
    event.preventDefault();
    item.onSelect();
  }

  if (!item.href) return null;

  return (
    <a
      aria-label="Back to calls"
      className="hidden shrink-0 items-center gap-1 rounded-sm text-[var(--admin-ink)] underline-offset-4 hover:underline max-sm:inline-flex"
      href={item.href}
      onClick={handleClick}
    >
      <ArrowLeft aria-hidden="true" className="size-3.5" />
      <span>Calls</span>
    </a>
  );
}
