import { useId, useState, type ReactNode } from "react";
import { ListFilter, ShieldCheck, Wrench } from "lucide-react";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@vxpipe/react";
import { Icon } from "../../../../../../packages/react/src/Icon";
import { SetupDialog } from "../SetupDialog";

const visibility = ["Show", "Hide"] as const;
const options = {
  messages: visibility,
  logs: visibility,
  events: ["Hide", "Call events", "Call + technical events"],
  tools: ["Hide", "Only calls", "With details"],
  guardrails: ["Hide", "Only failures", "All"],
} as const;

export type HistoryFilters = { [K in keyof typeof options]: (typeof options)[K][number] };

const eventDescriptions: Partial<Record<HistoryFilters["events"], string>> = {
  "Call events": "Shows call activity such as “Call connected”.",
  "Call + technical events": "Also include turn, transcript, delivery, and usage events.",
};

export function HistoryFilterButton({ filters, change, theme }: {
  filters: HistoryFilters;
  change: (value: HistoryFilters) => void;
  theme: "light" | "dark";
}) {
  const [open, setOpen] = useState(false);
  const id = useId();

  function row(key: keyof HistoryFilters, label: string, icon: ReactNode) {
    const labelId = id + key;
    return <div className="gh-option">
      <span className="gh-option-label" id={labelId}>{icon}{label}</span>
      <Select value={filters[key]} onValueChange={value => change({ ...filters, [key]: value })}>
        <SelectTrigger className="gh-option-trigger" aria-labelledby={labelId}>
          <SelectValue>{filters[key]}</SelectValue>
        </SelectTrigger>
        <SelectContent className="gh-option-menu" theme={theme} align="end" collisionPadding={12}
          onEscapeKeyDown={event => event.stopPropagation()}>
          {options[key].map((value, index) => {
            const description = key === "events" ? eventDescriptions[value as HistoryFilters["events"]] : undefined;
            const optionId = labelId + "-" + index;
            return <SelectItem key={value} value={value} textValue={value} aria-labelledby={optionId}
              aria-describedby={description ? optionId + "-description" : undefined}>
              <span id={optionId}>{value}</span>
              {description && <small id={optionId + "-description"} className="gh-choice-description">{description}</small>}
            </SelectItem>;
          })}
        </SelectContent>
      </Select>
    </div>;
  }

  return <>
    <button type="button" className="gh-filter-button" aria-haspopup="dialog" aria-expanded={open}
      onClick={() => setOpen(true)}><ListFilter size={16} />Filters</button>
    {open && <SetupDialog title="Conversation filters" initialFocusSelector=".gh-option-trigger" onClose={() => setOpen(false)}>
      <div className="gh-filter-body">
        {row("messages", "Messages", <Icon name="message" />)}
        {row("logs", "Logs", <Icon name="log" />)}
        {row("events", "Events", <Icon name="event" />)}
        {row("tools", "Tools", <Wrench aria-hidden="true" />)}
        {row("guardrails", "Guardrails", <ShieldCheck aria-hidden="true" />)}
      </div>
    </SetupDialog>}
  </>;
}
