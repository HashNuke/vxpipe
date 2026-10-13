import { useContext, useEffect, type ReactNode } from "react";
import { AdminLayoutContext, AdminOverlayContext } from "./AdminLayoutContext";

import { Breadcrumbs, type BreadcrumbItem } from "./Breadcrumbs";
import { useInputModality } from "./input-modality";

export function AdminShell({
  breadcrumbs,
  children,
  className,
  headerActions,
  headerInert = false,
  showHeader = true,
  theme = "dark",
}: {
  breadcrumbs?: BreadcrumbItem[];
  children: ReactNode;
  className?: string;
  headerActions?: ReactNode;
  headerInert?: boolean;
  showHeader?: boolean;
  theme?: "dark" | "light";
}) {
  useInputModality();
  const embedded = useContext(AdminLayoutContext);
  const setOverlay = useContext(AdminOverlayContext);
  useEffect(() => {
    if (!embedded) return;
    setOverlay(headerInert);
    return () => setOverlay(false);
  }, [embedded, headerInert, setOverlay]);
  if (embedded) return <>{children}</>;
  return (
    <div className={`vx-admin${className ? ` ${className}` : ""}`} data-theme={theme}>
      {showHeader ? (
        <header
          aria-hidden={headerInert ? "true" : undefined}
          className="bg-[var(--admin-panel)]"
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
