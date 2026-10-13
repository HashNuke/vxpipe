import { useEffect, useRef, useState, type ReactNode } from "react";
import { Building2, FileCode2, LogOut, Menu, Phone, Plug, ShieldCheck, UserRound, Users, X } from "lucide-react";
import { Dialog } from "radix-ui";
import { shouldInterceptNavigation } from "../shouldInterceptNavigation";
import { AdminOverlayContext } from "../AdminLayoutContext";
import { AdminShell } from "../AdminShell";
import type { Role, Tenant, Theme, User } from "../authentication/types";
import { allTenants, navigationItems, type NavigationItem } from "./navigationPolicy";
import { TenantPicker } from "./TenantPicker";
import "./navigation.css";
const icons = { Calls: Phone, "Call Specs": FileCode2, Services: Plug, Tenants: Building2, Roles: ShieldCheck, Users };
export function NavigationShell({ children, role, user, tenants, selected, path, onNavigate, onLogout, theme, pickerState, onRetry, projectedItems, directoryPath, picker, realLinks = false, email, external = false }: {
  children: ReactNode; role?: Role; user?: User; tenants: Tenant[]; selected?: Tenant; path: string;
  onNavigate: (path: string) => void; onLogout: () => void; theme: Theme;
  projectedItems?: { tenant: NavigationItem[]; platform: NavigationItem[] }; directoryPath?: string; picker?: ReactNode; realLinks?: boolean; email?: string; external?: boolean;
  pickerState?: "ready" | "loading" | "unavailable"; onRetry: () => void;
}) {
  const [overlay, setOverlay] = useState(false);
  const [open, setOpen] = useState(false);
  useEffect(() => setOpen(false), [path]);
  const main = useRef<HTMLDivElement>(null);
  const items = projectedItems ?? (role && user ? navigationItems(role, user, selected) : { tenant: [], platform: [] });
  const href = (path: string) => realLinks ? path : `#${path}`;
  function navigate(next: string) { setOpen(false); onNavigate(next); requestAnimationFrame(() => main.current?.focus()); }
  const rail = <>
    <a href={href("/")} className="navigation-brand" onClick={event => { if (!shouldInterceptNavigation(event)) return; event.preventDefault(); navigate("/"); }}>Vxpipe</a>
    {picker ?? <TenantPicker tenants={tenants} selected={selected} directoryPath={directoryPath ?? (role && allTenants(role) ? "/tenants" : "/my-tenants")} onNavigate={navigate} state={pickerState} onRetry={onRetry} realLinks={realLinks} />}
    <div className="navigation-groups">
      {(["tenant", "platform"] as const).map(group => items[group].length ? <nav key={group} aria-label={group === "tenant" ? "Tenant" : "Platform"}>
        <h2>{group === "tenant" ? "Tenant" : "Platform"}</h2>
        {items[group].map(item => { const Icon = icons[item.label as keyof typeof icons]; return <a key={item.href} href={href(item.href)} aria-current={path === item.href || path.startsWith(`${item.href}/`) ? "page" : undefined} onClick={event => { if (!shouldInterceptNavigation(event)) return; event.preventDefault(); navigate(item.href); }}><Icon size={17} aria-hidden />{item.label}</a>; })}
      </nav> : group === "tenant" && !selected ? <p key={group} className="navigation-prompt">Select a tenant to open its workspace.</p> : null)}
    </div>
    <div className="navigation-account"><span title={email ?? user?.email}>{email ?? user?.email}</span>
      <a href={href("/account")} aria-current={path === "/account" ? "page" : undefined} onClick={event => { if (!shouldInterceptNavigation(event)) return; event.preventDefault(); navigate("/account"); }}><UserRound size={17} aria-hidden />My account</a>
      <button onClick={onLogout}><LogOut size={17} aria-hidden />Logout</button>
    </div>
  </>;
  return <AdminShell showHeader={false} theme={theme} className={external ? "navigation-external-host" : undefined}><div className={`navigation-layout${external ? " navigation-external" : ""}`}>
    <a className="navigation-skip" href="#navigation-content">Skip to content</a>
    <aside inert={overlay || undefined} className="navigation-rail" aria-label="Console navigation">{rail}</aside>
    <div className="navigation-workspace">
      <Dialog.Root open={open} onOpenChange={setOpen}><div inert={overlay || undefined} className="navigation-mobile"><Dialog.Trigger asChild><button><Menu size={18} aria-hidden />Menu</button></Dialog.Trigger><span>{selected?.name ?? "Vxpipe"}</span></div>
        <Dialog.Portal><Dialog.Overlay className="navigation-backdrop" /><Dialog.Content className="navigation-drawer vx-admin" data-theme={theme} aria-describedby={undefined}>
          <Dialog.Title className="sr-only">Console navigation</Dialog.Title><Dialog.Close className="navigation-close" aria-label="Close navigation"><X size={18} /></Dialog.Close>{rail}
        </Dialog.Content></Dialog.Portal>
      </Dialog.Root>
      <div id={external ? undefined : "navigation-content"} className="navigation-content" tabIndex={-1} ref={main}><AdminOverlayContext value={setOverlay}>{children}</AdminOverlayContext></div>
    </div>
  </div></AdminShell>;
}
