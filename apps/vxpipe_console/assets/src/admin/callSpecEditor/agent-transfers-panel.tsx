import { useState } from "react";
import { Bot, Handshake, Plus, Search, Trash2 } from "lucide-react";
import { Button } from "../components/ui/button";
import { Input } from "../components/ui/input";
import { Popover, PopoverContent, PopoverTrigger } from "../components/ui/popover";
import { ChoiceField, NumberField } from "./editor-fields";
import { editSource } from "./editSource";
import { agent } from "./edits";
import type { InspectorProps } from "./inspectorTypes";
import { isTransferDestination, setTransfer } from "./participants";
import type { TransferHistory } from "./types";

export function AgentTransfersPanel({ document, onChange, issues, participantKey }: InspectorProps & { participantKey: string }) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const target = agent(document.source, participantKey);
  const transfers = target.transfers ?? [];
  const path = ["participants", participantKey];
  const available = Object.entries(document.source.participants).filter(([key, value]) => key !== participantKey && !transfers.includes(key) && isTransferDestination(document.source, key) && `${key} ${value.description ?? ""}`.toLowerCase().includes(query.trim().toLowerCase()));
  function history(value: TransferHistory | undefined) {
    onChange(editSource(document, (source) => { const target = agent(source, participantKey); if (value === undefined) delete target.transfer_history; else target.transfer_history = value; }));
  }
  return <div className="space-y-5">
    <section className="space-y-3" aria-label="Allowed destinations">
      <div className="flex items-center justify-between gap-3"><h3 className="text-sm font-medium">Allowed destinations</h3>
        <Popover open={open} onOpenChange={(open) => { setOpen(open); if (!open) setQuery(""); }}><PopoverTrigger asChild><Button variant="secondary" size="sm" disabled={document.readOnly}><Plus className="h-4 w-4" />Add destination</Button></PopoverTrigger>
          <PopoverContent align="end" className="w-80 max-w-[calc(100vw-2rem)] p-2">
            <div className="mb-2 flex items-center gap-2"><Search className="h-4 w-4 shrink-0 text-muted-foreground" /><Input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search destinations" aria-label="Search destinations" /></div>
            <div className="max-h-60 overflow-auto">{available.map(([key, value]) => {
              const Icon = value.type === "agent" ? Bot : Handshake;
              return <Button key={key} variant="ghost" className="h-auto w-full justify-start gap-3 px-2 py-2 text-left" aria-label={`Add ${key}`} onClick={() => { onChange(setTransfer(document, participantKey, key, true)); setOpen(false); setQuery(""); }}>
                <Icon className="h-4 w-4 shrink-0 text-muted-foreground" /><span className="min-w-0 whitespace-normal"><span className="block wrap-anywhere font-medium">{key}</span>{value.description && <span className="block wrap-anywhere text-xs font-normal text-muted-foreground">{value.description}</span>}</span>
              </Button>;
            })}{!available.length && <p className="px-3 py-6 text-center text-sm text-muted-foreground">No destinations match. Add a participant or change the search.</p>}</div>
          </PopoverContent>
        </Popover>
      </div>
      {transfers.map((key, index) => {
        const destination = Object.hasOwn(document.source.participants, key) ? document.source.participants[key] : undefined;
        const errors = issues?.filter((issue) => issue.path.join("\0") === [...path, "transfers", String(index)].join("\0")) ?? [];
        return <div key={`${key}:${index}`} className="rounded-md border border-border/70 bg-card p-3" data-field-path={JSON.stringify([...path, "transfers", String(index)])}>
          <div className="flex items-start justify-between gap-3"><div className="min-w-0"><p className="wrap-anywhere text-sm font-semibold">{key}</p><p className="mt-1 wrap-anywhere text-xs text-muted-foreground">{destination?.description || (destination ? destination.type === "agent" ? "Agent" : "Human destination" : "Missing participant")}</p></div>
            <Button variant="ghost" size="icon-sm" disabled={document.readOnly} aria-label={`Remove transfer to ${key}`} onClick={() => onChange(setTransfer(document, participantKey, key, false))}><Trash2 className="h-4 w-4" /></Button>
          </div>{errors.map((issue, index) => <p key={index} className="mt-2 text-xs text-destructive">{issue.reason}</p>)}
        </div>;
      })}
      {!transfers.length && <p className="rounded-md border border-dashed p-6 text-center text-sm text-muted-foreground">Add a destination to let this agent transfer the call.</p>}
    </section>
    <ChoiceField label="Transfer history" path={[...path, "transfer_history", "mode"]} issues={issues} disabled={document.readOnly} value={target.transfer_history?.mode ?? ""}
      choices={[{ value: "", label: "Default (fresh)" }, { value: "fresh", label: "Fresh" }, { value: "all_spoken", label: "All spoken history" }, { value: "last_n_spoken", label: "Last spoken turns" }, { value: "selected", label: "Selected history" }]}
      hint="Choose the history this agent receives when a call transfers to it."
      onChange={(mode) => history(mode === "last_n_spoken" ? { mode, turns: 1 } : mode === "fresh" || mode === "all_spoken" || mode === "selected" ? { mode } : undefined)} />
    {target.transfer_history?.mode === "last_n_spoken" && <NumberField label="Spoken turns" path={[...path, "transfer_history", "turns"]} issues={issues} disabled={document.readOnly} value={target.transfer_history.turns} hint="At least one spoken turn." onChange={(turns) => history({ mode: "last_n_spoken", turns: turns ?? 0 })} />}
  </div>;
}
