import { ChevronLeft, ChevronRight } from "lucide-react";

import { Button } from "./Button";
import type { PaginationModel } from "./tenantTypes";

export function Pagination({
  pagination,
  onPrevious,
  onNext,
}: {
  pagination: PaginationModel;
  onPrevious?: () => void;
  onNext?: () => void;
}) {
  return (
    <nav
      aria-label="Tenant pages"
      className="flex items-center justify-between gap-4 border-t border-[var(--admin-line)] px-3 py-3 sm:px-4"
    >
      <span className="font-mono text-xs tabular-nums text-[var(--admin-muted)]">
        {pagination.label}
      </span>
      <div className="flex gap-2">
        <Button
          aria-label="Previous page"
          disabled={!pagination.hasPrevious}
          onClick={onPrevious}
          type="button"
        >
          <ChevronLeft aria-hidden="true" className="size-4" />
          <span className="max-sm:sr-only">Previous</span>
        </Button>
        <Button
          aria-label="Next page"
          disabled={!pagination.hasNext}
          onClick={onNext}
          type="button"
        >
          <span className="max-sm:sr-only">Next</span>
          <ChevronRight aria-hidden="true" className="size-4" />
        </Button>
      </div>
    </nav>
  );
}
