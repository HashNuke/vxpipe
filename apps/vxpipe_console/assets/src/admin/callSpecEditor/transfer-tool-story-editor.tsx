import { useState } from "react";
import { Check, ChevronsUpDown, X } from "lucide-react";
import { Badge } from "../components/ui/badge";
import { Button } from "../components/ui/button";
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "../components/ui/command";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "../components/ui/dialog";
import { Popover, PopoverContent, PopoverTrigger } from "../components/ui/popover";
import { agent } from "./edits";
import { isTransferDestination, setTransfer } from "./participants";
import type { InspectorProps } from "./inspectorTypes";

export function TransferToolStoryEditor({ document, onChange, participantKey, onClose }: InspectorProps & {
  participantKey: string; onClose: () => void;
}) {
  const saved = agent(document.source, participantKey).transfers ?? [];
  const [selected, setSelected] = useState(saved);
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const eligible = Object.keys(document.source.participants).filter(key => key !== participantKey && isTransferDestination(document.source, key)).sort();
  function toggle(key: string) {
    setSelected(current => current.includes(key) ? current.filter(value => value !== key) : [...current, key]);
    setQuery("");
  }
  function save() {
    let next = document;
    for (const key of saved) if (!selected.includes(key)) next = setTransfer(next, participantKey, key, false);
    for (const key of selected) if (!saved.includes(key)) next = setTransfer(next, participantKey, key, true);
    onChange(next);
    onClose();
  }
  return <Dialog open onOpenChange={visible => { if (!visible) onClose(); }}>
    <DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-md">
      <DialogHeader className="text-left"><DialogTitle>{saved.length ? "Edit tool" : "Add tool"}</DialogTitle><DialogDescription>platform · transfer</DialogDescription></DialogHeader>
      <section className="space-y-2">
        <h3 className="text-sm font-medium">Allowed destinations</h3>
        <Popover open={open} onOpenChange={visible => { setOpen(visible); setQuery(""); }}>
          <div className="relative flex min-h-10 items-center rounded-md border border-control-border bg-background focus-within:ring-2 focus-within:ring-ring">
            <div className="flex min-w-0 flex-wrap gap-1 py-1.5 pl-2">
              {selected.map(key => <Badge key={key} variant="outline" className="max-w-full bg-control pr-0.5"><span className="truncate">{key}</span>
                <Button variant="ghost" size="icon-sm" className="size-6" aria-label={`Remove destination ${key}`} onClick={() => toggle(key)}><X className="size-3" /></Button>
              </Badge>)}
              {!selected.length && <span className="text-sm text-muted-foreground">Choose participants</span>}
            </div>
            <PopoverTrigger asChild><Button variant="ghost" role="combobox" aria-expanded={open} aria-label="Allowed destinations" className="min-h-9 min-w-10 flex-1 self-stretch justify-end px-2"><ChevronsUpDown className="size-4" /></Button></PopoverTrigger>
          </div>
          <PopoverContent align="end" className="w-[min(24rem,calc(100vw-4rem))] p-0">
            <Command loop label="Participants"><CommandInput aria-label="Search participants" placeholder="Search participants…" value={query} onValueChange={setQuery} />
              <CommandList><CommandEmpty>No matching participants.</CommandEmpty><CommandGroup>
                {eligible.map(key => <CommandItem key={key} value={key} onSelect={() => toggle(key)}>
                  <Check className={selected.includes(key) ? "size-4" : "invisible size-4"} />{key}
                  {selected.includes(key) && <span className="sr-only">selected</span>}
                </CommandItem>)}
              </CommandGroup></CommandList>
            </Command>
          </PopoverContent>
        </Popover>
      </section>
      <DialogFooter><Button variant="outline" onClick={onClose}>Cancel</Button><Button disabled={!selected.length} onClick={save}>Save tool</Button></DialogFooter>
    </DialogContent>
  </Dialog>;
}
