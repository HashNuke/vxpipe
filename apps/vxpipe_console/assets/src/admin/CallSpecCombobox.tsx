import * as Popover from "@radix-ui/react-popover";
import { Check, ChevronsUpDown, Search } from "lucide-react";
import { Command } from "cmdk";
import { useState } from "react";

import { classNames } from "./classNames";

type CallSpecOption = {
  id: string;
  name: string | null;
};

export function CallSpecCombobox({
  options,
  selectedId,
  unknownSelection,
  onSelect,
}: {
  options: CallSpecOption[];
  selectedId: string | null;
  unknownSelection: boolean;
  onSelect?: (definitionId: string | null) => void;
}) {
  const [open, setOpen] = useState(false);
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
    <Popover.Root onOpenChange={setOpen} open={open}>
      <Popover.Trigger asChild>
        <button
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
      <Popover.Portal>
        <Popover.Content
          align="start"
          className="z-50 w-[var(--radix-popover-trigger-width)] overflow-hidden rounded-md border border-[var(--admin-line)] bg-[var(--admin-panel)] text-[var(--admin-ink)] shadow-xl"
          collisionPadding={12}
          sideOffset={6}
        >
          <Command className="w-full" loop>
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
              />
            </div>
            <Command.List className="max-h-64 overflow-y-auto p-1">
              <Command.Empty className="px-3 py-6 text-center text-sm text-[var(--admin-muted)]">
                No call specs found.
              </Command.Empty>
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
              {options.map((option) => (
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
            </Command.List>
          </Command>
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}
