import { useState } from "react";
import { Check, ChevronsUpDown } from "lucide-react";
import { Button } from "../components/ui/button";
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "../components/ui/command";
import { Popover, PopoverContent, PopoverTrigger } from "../components/ui/popover";

type Props = {
  id: string;
  label: string;
  options: { value: string; label: string }[];
  multiple: boolean;
  value: string | string[] | undefined;
  onChange: (value: string | string[] | undefined) => void;
};

/** One searchable control; provider descriptors retain single/multiple cardinality. */
export function VoiceFilterSelect({ id, label, options, multiple, value, onChange }: Props) {
  const [open, setOpen] = useState(false);
  const selected = Array.isArray(value) ? value : value === undefined ? [] : [value];
  const names = options.filter(option => selected.includes(option.value)).map(option => option.label);
  return <Popover open={open} onOpenChange={setOpen}>
    <PopoverTrigger asChild><Button id={id} type="button" size="sm" variant="outline" role="combobox" aria-label={label} aria-expanded={open} className="w-full justify-between text-xs font-normal">
      <span className="truncate">{names.length ? names.join(", ") : "Any"}</span><ChevronsUpDown className="size-4 shrink-0 text-muted-foreground" />
    </Button></PopoverTrigger>
    <PopoverContent align="start" aria-label={`${label} filter`} className="w-[var(--radix-popover-trigger-width)] min-w-48 p-0">
      <Command label={`Search ${label.toLowerCase()}`}>
        <CommandInput className="text-xs" aria-label={`Search ${label.toLowerCase()}`} placeholder={`Search ${label.toLowerCase()}…`} />
        <CommandList aria-label={label}>
          <CommandEmpty className="py-4 text-center text-xs">No matches.</CommandEmpty>
          <CommandGroup>
            <CommandItem className="text-xs" value="Any" onSelect={() => { onChange(undefined); if (!multiple) setOpen(false); }}>
              <Check aria-hidden="true" className={selected.length ? "invisible" : ""} />Any
            </CommandItem>
            {options.map(option => <CommandItem className="text-xs" key={option.value} value={option.value} keywords={[option.label]} onSelect={() => {
              if (multiple) {
                const next = selected.includes(option.value) ? selected.filter(item => item !== option.value) : [...selected, option.value];
                onChange(next.length ? next : undefined);
              } else { onChange(option.value); setOpen(false); }
            }}>
              <Check aria-hidden="true" className={selected.includes(option.value) ? "" : "invisible"} />{option.label}
              {selected.includes(option.value) && <span className="sr-only">(selected)</span>}
            </CommandItem>)}
          </CommandGroup>
        </CommandList>
      </Command>
      {multiple && <div className="border-t p-1"><Button type="button" variant="ghost" size="sm" className="w-full text-xs" onClick={() => setOpen(false)}>Done</Button></div>}
    </PopoverContent>
  </Popover>;
}
