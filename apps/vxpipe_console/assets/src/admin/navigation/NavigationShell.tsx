import { useEffect, useRef, useState, type ReactNode } from "react";
import { ArrowLeft, Settings, Building2, KeyRound, FileCode2, LogOut, Menu, Phone, Plug, ShieldCheck, UserRound, Users, X } from "lucide-react";
import { Dialog } from "radix-ui";
import { shouldInterceptNavigation } from "../shouldInterceptNavigation";
import { AdminOverlayContext } from "../AdminLayoutContext";
import { AdminShell } from "../AdminShell";
import type { Role, Tenant, Theme, User } from "../authentication/types";
import { navigationItems, type NavigationItem } from "./navigationPolicy";
import { TenantPicker } from "./TenantPicker";
import "./navigation.css";
const icons = { "API Keys": KeyRound, Calls: Phone, "Call Specs": FileCode2, Services: Plug, Tenants: Building2, Roles: ShieldCheck, Users };
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
  const settings = /^\/(api-keys|roles|users|platform)(\/|$)/.test(path);
  const href = (path: string) => realLinks ? path : `#${path}`;
  function navigate(next: string) { setOpen(false); onNavigate(next); requestAnimationFrame(() => main.current?.focus()); }
  const rail = <>
    {settings ? <>
      <a href={href("/tenants")} className="navigation-back" onClick={event => { if (!shouldInterceptNavigation(event)) return; event.preventDefault(); navigate("/tenants"); }}><ArrowLeft size={17} aria-hidden />Back to tenants</a>
      <div className="navigation-settings-title">Settings</div>
    </> : <>
      <a href={href("/")} className="navigation-brand" onClick={event => { if (!shouldInterceptNavigation(event)) return; event.preventDefault(); navigate("/"); }}>Vxpipe</a>
      {picker ?? <TenantPicker tenants={tenants} selected={selected} directoryPath={directoryPath ?? "/tenants"} onNavigate={navigate} state={pickerState} onRetry={onRetry} realLinks={realLinks} />}
    </>}
    <div className={`navigation-groups${settings ? " navigation-settings-groups" : ""}`}>
      {!settings ? <nav aria-label="Tenants"><a href={href("/tenants")} aria-current={path === "/tenants" || path.startsWith("/tenants/") ? "page" : undefined} onClick={event => { if (!shouldInterceptNavigation(event)) return; event.preventDefault(); navigate("/tenants"); }}><Building2 size={17} aria-hidden />Tenants</a></nav> : null}
      {(settings ? items.platform : items.tenant).length ? <nav aria-label={settings ? "Settings" : "Tenant"}>
        {!settings ? <h2>Tenant</h2> : null}
        {(settings ? items.platform : items.tenant).map(item => { const Icon = icons[item.label as keyof typeof icons]; return <a key={item.href} href={href(item.href)} aria-current={path === item.href || path.startsWith(`${item.href}/`) ? "page" : undefined} onClick={event => { if (!shouldInterceptNavigation(event)) return; event.preventDefault(); navigate(item.href); }}><Icon size={17} aria-hidden />{item.label}</a>; })}
      </nav> : null}
      {!settings && items.platform.length ? <nav aria-label="Workspace settings"><a href={href(items.platform[0].href)} onClick={event => { if (!shouldInterceptNavigation(event)) return; event.preventDefault(); navigate(items.platform[0].href); }}><Settings size={17} aria-hidden />Settings</a></nav> : null}
    </div>
    <div className="navigation-account"><span title={email ?? user?.email}>{email ?? user?.email}</span>
      {!settings ? <a href={href("/account")} aria-current={path === "/account" ? "page" : undefined} onClick={event => { if (!shouldInterceptNavigation(event)) return; event.preventDefault(); navigate("/account"); }}><UserRound size={17} aria-hidden />My account</a> : null}
      <button onClick={onLogout}><LogOut size={17} aria-hidden />Logout</button>
    </div>
  </>;
  return <AdminShell showHeader={false} theme={theme} className={external ? "navigation-external-host" : undefined}><div className={`navigation-layout${external ? " navigation-external" : ""}`}>
    <a className="navigation-skip" href="#navigation-content">Skip to content</a>
    <aside inert={overlay || undefined} className="navigation-rail" aria-label="Console navigation">{rail}</aside>
    <div className="navigation-workspace">
      <Dialog.Root open={open} onOpenChange={setOpen}><div inert={overlay || undefined} className="navigation-mobile"><Dialog.Trigger asChild><button><Menu size={18} aria-hidden />Menu</button></Dialog.Trigger><span>{settings ? "Settings" : selected?.name ?? "Vxpipe"}</span></div>
        <Dialog.Portal><Dialog.Overlay className="navigation-backdrop" /><Dialog.Content className="navigation-drawer vx-admin" data-theme={theme} aria-describedby={undefined}>
          <Dialog.Title className="sr-only">Console navigation</Dialog.Title><Dialog.Close className="navigation-close" aria-label="Close navigation"><X size={18} /></Dialog.Close>{rail}
        </Dialog.Content></Dialog.Portal>
      </Dialog.Root>
      <div id={external ? undefined : "navigation-content"} className="navigation-content" tabIndex={-1} ref={main}><AdminOverlayContext value={setOverlay}>{children}</AdminOverlayContext></div>
    </div>
  </div></AdminShell>;
}
