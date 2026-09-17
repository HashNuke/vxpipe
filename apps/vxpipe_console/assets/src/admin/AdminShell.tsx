import type { ReactNode } from "react";

export function AdminShell({
  children,
  headerActions,
  showHeader = true,
  theme = "dark",
}: {
  children: ReactNode;
  headerActions?: ReactNode;
  showHeader?: boolean;
  theme?: "dark" | "light";
}) {
  return (
    <div className="vx-admin" data-theme={theme}>
      {showHeader ? (
        <header className="border-b border-[var(--admin-line)] bg-[var(--admin-panel)]">
          <div className="mx-auto flex min-h-16 w-full max-w-[1600px] items-center gap-8 px-4 sm:px-6">
            <span className="text-base font-bold tracking-[-0.03em]">Vxpipe</span>
            <nav aria-label="Primary navigation" className="self-stretch">
              <span
                aria-current="page"
                className="flex h-full items-center border-b-2 border-[var(--admin-ink)] font-mono text-xs font-bold uppercase tracking-[0.05em]"
              >
                Admin
              </span>
            </nav>
            {headerActions ? <div className="ml-auto">{headerActions}</div> : null}
          </div>
        </header>
      ) : null}
      {children}
    </div>
  );
}
