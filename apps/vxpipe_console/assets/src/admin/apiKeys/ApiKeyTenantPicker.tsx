import { useEffect, useState, useCallback } from "react";
import * as Popover from "@radix-ui/react-popover";
import { Command } from "cmdk";
import { Check, ChevronsUpDown } from "lucide-react";
import type { AccessKeysClient, KeyKind, KeyTenant } from "./accessKeysApi";

export function ApiKeyTenantPicker({ api, kind, selected, onSelect, disabled }: { api: AccessKeysClient; kind: KeyKind; selected: KeyTenant | null; onSelect: (tenant: KeyTenant) => void; disabled: boolean }) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(1);
  const [items, setItems] = useState<KeyTenant[]>([]);
  const [more, setMore] = useState(false);
  const [state, setState] = useState<"loading" | "ready" | "error">("loading");
  const [container, setContainer] = useState<HTMLElement>();
  const bind = useCallback((node: HTMLButtonElement | null) => setContainer(node?.closest<HTMLElement>(".vx-admin") ?? undefined), []);
  useEffect(() => {
    if (!open) return;
    const controller = new AbortController();
    setState("loading");
    const timer = setTimeout(() => {
      api.tenants(kind, query, page, controller.signal).then(data => {
        if (controller.signal.aborted) return;
        setItems(old => page === 1 ? data.tenants : [...old, ...data.tenants.filter(t => !old.some(x => x.key === t.key))]);
        setMore(data.hasNext); setState("ready");
      }).catch(() => { if (!controller.signal.aborted) setState("error"); });
    }, query ? 200 : 0);
    return () => { clearTimeout(timer); controller.abort(); };
  }, [api, kind, open, query, page]);
  return <Popover.Root open={open} onOpenChange={value => { setOpen(value); if (value) { setQuery(""); setPage(1); setItems([]); } }}>
    <Popover.Trigger asChild><button ref={bind} type="button" role="combobox" aria-expanded={open} aria-label="Tenant" disabled={disabled}
      className="flex min-h-10 w-full items-center justify-between gap-3 rounded-md border border-[var(--admin-line)] bg-[var(--admin-panel)] px-3 text-left text-sm">
      <span className="truncate">{selected?.name ?? "Select a tenant"}</span><ChevronsUpDown className="size-4 shrink-0 text-[var(--admin-muted)]" aria-hidden />
    </button></Popover.Trigger>
    <Popover.Portal container={container}><Popover.Content align="start" sideOffset={6} collisionPadding={12} className="z-50 w-[var(--radix-popover-trigger-width)] rounded-md border border-[var(--admin-line)] bg-[var(--admin-panel)] text-[var(--admin-ink)] shadow-lg">
      <Command shouldFilter={false} loop label="Search tenants"><Command.Input aria-label="Search tenants" placeholder="Search tenants…" value={query} onValueChange={value => { setQuery(value); setPage(1); setItems([]); }} className="h-10 w-full border-b border-[var(--admin-line)] bg-transparent px-3 text-sm outline-none" />
        <Command.List className="max-h-64 overflow-auto p-1">
          {state === "loading" ? <p role="status" className="p-3 text-sm text-[var(--admin-muted)]">Searching…</p> : state === "error" ? <p role="alert" className="p-3 text-sm">Could not load tenants.</p> : <>
            {!items.length ? <p className="p-3 text-sm text-[var(--admin-muted)]">No eligible tenants found.</p> : items.map(item => <Command.Item key={item.key} value={item.key} onSelect={() => { onSelect(item); setOpen(false); }} className="flex cursor-pointer items-center justify-between rounded-sm px-3 py-2 text-sm data-[selected=true]:bg-[var(--admin-soft)]">{item.name}{selected?.key === item.key ? <Check size={14} aria-hidden /> : null}</Command.Item>)}
            {more ? <Command.Item value="load-more" onSelect={() => setPage(p => p + 1)} className="cursor-pointer px-3 py-2 text-sm data-[selected=true]:bg-[var(--admin-soft)]">Load more</Command.Item> : null}
          </>}
        </Command.List>
      </Command>
    </Popover.Content></Popover.Portal>
  </Popover.Root>;
}
