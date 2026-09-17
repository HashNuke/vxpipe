import { ChevronRight } from "lucide-react";
import type { MouseEvent } from "react";

import { shouldInterceptNavigation } from "./shouldInterceptNavigation";

export type BreadcrumbItem = {
  label: string;
  href?: string;
  onSelect?: () => void;
};

export function Breadcrumbs({ items }: { items: BreadcrumbItem[] }) {
  function handleClick(
    event: MouseEvent<HTMLAnchorElement>,
    onSelect: (() => void) | undefined,
  ) {
    if (!onSelect || !shouldInterceptNavigation(event)) return;
    event.preventDefault();
    onSelect();
  }

  return (
    <nav aria-label="Breadcrumb" className="mb-4">
      <ol className="flex min-w-0 items-center gap-1 text-sm text-[var(--admin-muted)]">
        {items.map((item, index) => (
          <li className="flex min-w-0 items-center gap-1" key={`${item.label}-${index}`}>
            {index > 0 ? (
              <ChevronRight aria-hidden="true" className="size-3.5 shrink-0" />
            ) : null}
            {item.href ? (
              <a
                className="truncate rounded-sm text-inherit underline-offset-4 hover:text-[var(--admin-ink)] hover:underline"
                href={item.href}
                onClick={(event) => handleClick(event, item.onSelect)}
              >
                {item.label}
              </a>
            ) : (
              <span aria-current="page" className="truncate text-[var(--admin-ink)]">
                {item.label}
              </span>
            )}
          </li>
        ))}
      </ol>
    </nav>
  );
}
