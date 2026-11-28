import { useState, type ReactNode } from "react";
import { ListFilter, ShieldCheck, Wrench } from "lucide-react";
import { Icon } from "../../../../../../packages/react/src/Icon";
import { SetupDialog } from "../SetupDialog";

export type HistoryFilters = {
  messages: boolean; logs: boolean; events: boolean; technical: boolean;
  tools: boolean; toolDetails: boolean; guardrails: "None" | "Only failures" | "All";
};
export const presets: Record<"Info" | "Debug" | "All", HistoryFilters> = {
  Info: { messages: true, logs: false, events: false, technical: false, tools: true, toolDetails: false, guardrails: "None" },
  Debug: { messages: true, logs: false, events: true, technical: false, tools: true, toolDetails: true, guardrails: "Only failures" },
  All: { messages: true, logs: true, events: true, technical: true, tools: true, toolDetails: true, guardrails: "All" },
};

export function HistoryFilterButton({ filters, change }: { filters: HistoryFilters; change: (value: HistoryFilters) => void }) {
  const [open, setOpen] = useState(false);
  const effective = {...filters, technical: filters.events && filters.technical};
  const row = (key: "messages" | "logs" | "events" | "tools", label: string, icon: ReactNode) => {
    return <label className="gh-option">{icon}{label}
      <input type="checkbox" checked={filters[key]} onChange={e => change({ ...filters, [key]: e.target.checked })} />
    </label>;
  };
  return <>
    <button type="button" className="gh-filter-button" aria-haspopup="dialog" aria-expanded={open}
      onClick={() => setOpen(true)}><ListFilter size={16} />Filters</button>
    {open && <SetupDialog title="Conversation filters" initialFocusSelector=".gh-presets button" onClose={() => setOpen(false)}>
      <div className="gh-filter-body">
        <div className="gh-presets" role="group" aria-label="Preset">{Object.entries(presets).map(([name, value]) =>
          <button type="button" key={name} aria-pressed={Object.entries(value).every(([k,v]) => effective[k as keyof HistoryFilters] === v)}
            onClick={() => change(value)}>{name}</button>)}</div>
        {row("messages", "Messages", <Icon name="message" />)}
        {row("logs", "Logs", <Icon name="log" />)}
        {row("events", "Events", <Icon name="event" />)}
        {filters.events && <label className="gh-suboption">Include technical events
          <input type="checkbox" checked={filters.technical} onChange={e => change({...filters, technical: e.target.checked})} /></label>}
        {row("tools", "Tools", <Wrench aria-hidden="true" />)}
        {filters.tools && <label className="gh-suboption">Tool detail
          <select value={filters.toolDetails ? "With details" : "Only calls"} onChange={e => change({...filters, toolDetails: e.target.value === "With details"})}>
            <option>Only calls</option><option>With details</option></select></label>}
        <label className="gh-option"><ShieldCheck aria-hidden="true" />Guardrails
          <select value={filters.guardrails} onChange={e => change({...filters, guardrails: e.target.value as HistoryFilters["guardrails"]})}>
            <option>None</option><option>Only failures</option><option>All</option></select></label>
      </div>
    </SetupDialog>}
  </>;
}
