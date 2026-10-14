import * as Popover from "@radix-ui/react-popover";
import { Check, ChevronsUpDown, Search } from "lucide-react";
import { Command } from "cmdk";
import { useCallback, useEffect, useState } from "react";

import { classNames } from "./classNames";
import type { CallSpecOption, CallSpecSearch } from "./callSpecSearch";

export function CallSpecCombobox({
  options,
  selectedId,
  unknownSelection,
  onSelect,
  search,
}: {
  search?: CallSpecSearch;
  options: CallSpecOption[];
  selectedId: string | null;
  unknownSelection: boolean;
  onSelect?: (callSpecId: string | null) => void;
}) {
  const [portalContainer, setPortalContainer] = useState<HTMLElement>();
  const bindTrigger = useCallback((node: HTMLButtonElement | null) => {
    setPortalContainer(node?.closest<HTMLElement>(".vx-admin") ?? undefined);
  }, []);
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(1);
  const [remote, setRemote] = useState<{
    options: CallSpecOption[];
    hasMore: boolean;
  }>({ options: [], hasMore: false });
  const [status, setStatus] = useState<"loading" | "ready" | "error">("loading");
  useEffect(() => {
    if (!open || !search) return;
    const controller = new AbortController();
    setStatus("loading");
    const timer = window.setTimeout(() => {
      search(query, page, controller.signal)
        .then((result) => {
          if (controller.signal.aborted) return;
          setRemote((previous) => ({
            ...result,
            options: page === 1 ? result.options : [
              ...previous.options,
              ...result.options.filter((item) =>
                !previous.options.some(({ id }) => id === item.id),
              ),
            ],
          }));
          setStatus("ready");
        })
        .catch(() => {
          if (!controller.signal.aborted) setStatus("error");
        });
    }, query ? 200 : 0);
    return () => {
      window.clearTimeout(timer);
      controller.abort();
    };
  }, [open, search, query, page]);
  const visibleOptions = search ? remote.options : options;
  const selected = options.find(({ id }) => id === selectedId);
  const selectedLabel = unknownSelection
    ? "Unknown call spec"
    : selected
      ? (selected.name ?? selected.id)
      : "All call specs";

  function choose(value: string) {
    onSelect?.(value === "__all__" ? null : value);
    setOpen(false);
  }

  return (
    <Popover.Root
      open={open}
      onOpenChange={(value) => {
        setOpen(value);
        if (value) {
          setPage(1);
          setQuery("");
          setRemote({ options: [], hasMore: false });
          setStatus("loading");
        }
      }}
    >
      <Popover.Trigger asChild>
        <button
          ref={bindTrigger}
          aria-expanded={open}
          aria-label="Call spec"
          className="flex h-10 w-full items-center justify-between gap-2 rounded-sm border border-[var(--admin-line)] bg-[var(--admin-panel)] px-3 text-left text-sm text-[var(--admin-ink)] outline-none hover:bg-[var(--admin-soft)] focus-visible:ring-2 focus-visible:ring-[var(--admin-blue)]"
          role="combobox"
          type="button"
        >
          <span className="truncate">{selectedLabel}</span>
          <ChevronsUpDown
            aria-hidden="true"
            className="size-4 shrink-0 text-[var(--admin-muted)]"
          />
        </button>
      </Popover.Trigger>
      <Popover.Portal container={portalContainer}>
        <Popover.Content
          align="start"
          className="z-50 w-[var(--radix-popover-trigger-width)] overflow-hidden rounded-md border border-[var(--admin-line)] bg-[var(--admin-panel)] text-[var(--admin-ink)] shadow-xl"
          collisionPadding={12}
          sideOffset={6}
        >
          <Command className="w-full" loop shouldFilter={!search}>
            <div className="flex items-center gap-2 border-b border-[var(--admin-line)] px-3">
              <Search
                aria-hidden="true"
                className="size-4 shrink-0 text-[var(--admin-muted)]"
              />
              <Command.Input
                aria-label="Search call specs"
                autoFocus
                className="h-10 min-w-0 flex-1 border-0 bg-transparent text-sm outline-none placeholder:text-[var(--admin-muted)]"
                placeholder="Search call specs…"
                role="searchbox"
                value={query}
                onValueChange={(value) => {
                  setQuery(value);
                  setPage(1);
                  if (search) {
                    setRemote({ options: [], hasMore: false });
                    setStatus("loading");
                  }
                }}
              />
            </div>
            <Command.List className="max-h-64 overflow-y-auto p-1">
              {!search ? <Command.Empty className="px-3 py-6 text-center text-sm text-[var(--admin-muted)]">
                No call specs found.
              </Command.Empty> : null}
              <Command.Item
                className="flex cursor-default items-center gap-2 rounded-sm px-2 py-2 text-sm outline-none data-[selected=true]:bg-[var(--admin-soft)]"
                onSelect={choose}
                value="__all__"
              >
                <Check
                  aria-hidden="true"
                  className={classNames(
                    "size-4",
                    selectedId === null ? "opacity-100" : "opacity-0",
                  )}
                />
                All call specs
              </Command.Item>
              {unknownSelection ? (
                <Command.Item
                  className="flex cursor-default items-center gap-2 rounded-sm px-2 py-2 text-sm outline-none data-[selected=true]:bg-[var(--admin-soft)]"
                  disabled
                  value={selectedId ?? "__unknown__"}
                >
                  <Check aria-hidden="true" className="size-4" />
                  Unknown call spec
                </Command.Item>
              ) : null}
              {visibleOptions.map((option) => (
                <Command.Item
                  className="flex cursor-default items-center gap-2 rounded-sm px-2 py-2 text-sm outline-none data-[selected=true]:bg-[var(--admin-soft)]"
                  key={option.id}
                  keywords={[option.name ?? ""]}
                  onSelect={choose}
                  value={option.id}
                >
                  <Check
                    aria-hidden="true"
                    className={classNames(
                      "size-4",
                      selectedId === option.id ? "opacity-100" : "opacity-0",
                    )}
                  />
                  <span className="truncate">{option.name ?? option.id}</span>
                </Command.Item>
              ))}
              {search && status === "loading" ? (
                <div role="status" className="px-3 py-3 text-sm text-[var(--admin-muted)]">
                  Loading call specs…
                </div>
              ) : null}
              {search && status === "error" ? (
                <div role="alert" className="px-3 py-3 text-sm">Call specs could not be loaded.</div>
              ) : null}
              {search && status === "ready" && !remote.options.length ? (
                <div className="px-3 py-3 text-sm text-[var(--admin-muted)]">No call specs found.</div>
              ) : null}
            </Command.List>
            {search && remote.hasMore && status === "ready" ? (
              <button
                className="w-full border-t border-[var(--admin-line)] px-3 py-2 text-sm hover:bg-[var(--admin-soft)]"
                type="button"
                onClick={() => setPage((value) => value + 1)}
              >
                Load more
              </button>
            ) : null}
          </Command>
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}
