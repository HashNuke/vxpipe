import type { ReactNode } from "react";

import { Breadcrumbs, type BreadcrumbItem } from "./Breadcrumbs";

export function AdminShell({
  breadcrumbs,
  children,
  headerActions,
  headerInert = false,
  showHeader = true,
  theme = "dark",
}: {
  breadcrumbs?: BreadcrumbItem[];
  children: ReactNode;
  headerActions?: ReactNode;
  headerInert?: boolean;
  showHeader?: boolean;
  theme?: "dark" | "light";
}) {
  return (
    <div className="vx-admin" data-theme={theme}>
      {showHeader ? (
        <header
          aria-hidden={headerInert ? "true" : undefined}
          className="border-b border-[var(--admin-line)] bg-[var(--admin-panel)]"
          inert={headerInert ? true : undefined}
        >
          <div className="mx-auto flex min-h-12 w-full max-w-[1600px] items-center gap-3 px-4 sm:gap-6 sm:px-6">
            <span className="shrink-0 text-base font-bold tracking-[-0.03em]">Vxpipe</span>
            {breadcrumbs ? <Breadcrumbs compact current="location" items={breadcrumbs} /> : null}
            {headerActions ? <div className="ml-auto shrink-0">{headerActions}</div> : null}
          </div>
        </header>
      ) : null}
      {children}
    </div>
  );
}
