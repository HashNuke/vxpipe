import { shouldInterceptNavigation } from "../shouldInterceptNavigation";
import * as Popover from "@radix-ui/react-popover";
import { Command } from "cmdk";
import { Check, ChevronsUpDown, Search } from "lucide-react";
import { useState } from "react";
import type { Tenant } from "../authentication/types";

export function TenantPicker({ tenants, selected, directoryPath, onNavigate, state = "ready", onRetry, query, onQueryChange, onMore, onOpenChange, realLinks = false }: {
  tenants: Tenant[]; selected?: Tenant; directoryPath: string; onNavigate: (path: string) => void;
  onOpenChange?: (open: boolean) => void; query?: string; onQueryChange?: (query: string) => void; onMore?: () => void; realLinks?: boolean;
  state?: "ready" | "loading" | "unavailable"; onRetry: () => void;
}) {
  const [open, setOpen] = useState(false);
  const changeOpen = (value: boolean) => { setOpen(value); onOpenChange?.(value); };
  return <Popover.Root open={open} onOpenChange={changeOpen}>
    <Popover.Trigger asChild><button type="button" className="navigation-picker" role="combobox" aria-label="Switch tenant" aria-expanded={open}>
      <span title={selected?.name}>{selected?.name ?? "Select a tenant"}</span><ChevronsUpDown size={16} aria-hidden />
    </button></Popover.Trigger>
    <Popover.Content aria-label="Choose a tenant" className="navigation-picker-menu" align="start" sideOffset={6} collisionPadding={12}>
      <Command shouldFilter={!onQueryChange} loop label="Search tenants"><div className="navigation-search"><Search size={16} aria-hidden /><Command.Input maxLength={120} value={query} onValueChange={onQueryChange} aria-label="Search tenants" placeholder="Search tenants…" autoFocus /></div>
        <Command.List aria-label="Tenants">
          {state === "loading" ? <p role="status">Loading tenants…</p> : state === "unavailable" ? <div role="alert"><p>Tenants could not be loaded.</p><button onClick={onRetry}>Try again</button></div> : <>
            <Command.Empty>No matching tenants.</Command.Empty>
            {tenants.map(tenant => <Command.Item key={tenant.key} value={tenant.key} keywords={[tenant.name]} onSelect={() => { changeOpen(false); onNavigate(`/t/${encodeURIComponent(tenant.key)}/dashboard`); }}>
              <span><strong>{tenant.name}</strong><small>{tenant.key}</small></span>{selected?.key === tenant.key ? <Check size={15} aria-hidden /> : null}
            </Command.Item>)}
          </>}
        {onMore && state === "ready" ? <button type="button" className="navigation-picker-footer" onClick={onMore}>Load more tenants</button> : null}
        </Command.List>
      </Command>
      <a className="navigation-picker-footer" href={realLinks ? directoryPath : `#${directoryPath}`} onClick={event => { if (!shouldInterceptNavigation(event)) return; event.preventDefault(); changeOpen(false); onNavigate(directoryPath); }}>{directoryPath === "/tenants" ? "View all tenants" : "View my tenants"}</a>
    </Popover.Content>
  </Popover.Root>;
}
