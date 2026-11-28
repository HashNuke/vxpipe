import { useId, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { ListFilter, RotateCcw, ShieldCheck, Wrench, X } from "lucide-react";
import { Icon } from "./Icon.js";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "./Select.js";
import { historyOptions as options, type HistoryFilters } from "./historyFilters.js";

const eventDescriptions: Partial<Record<HistoryFilters["events"], string>> = {
  "Call events": "Shows call activity such as “Call connected”.",
  "Call + technical events": "Also include turn, transcript, delivery, and usage events.",
};

export function ConversationHistoryFilters({ filters, defaults, change, theme }: {
  filters: HistoryFilters;
  defaults: HistoryFilters;
  change: (value: HistoryFilters) => void;
  theme: "light" | "dark";
}) {
  const [open, setOpen] = useState(false);
  const id = useId();
  const trigger = useRef<HTMLButtonElement>(null);
  const [dialog, setDialog] = useState<HTMLDialogElement | null>(null);
  useLayoutEffect(() => {
    if (!dialog) return;
    if (typeof dialog.showModal === "function") dialog.showModal();
    else dialog.setAttribute("open", "");
    dialog.querySelector<HTMLButtonElement>('[role="combobox"]')?.focus();
    return () => { trigger.current?.focus(); };
  }, [dialog]);

  const atDefaults = (Object.keys(options) as (keyof HistoryFilters)[]).every(key => filters[key] === defaults[key]);

  function row(key: keyof HistoryFilters, label: string, icon: ReactNode) {
    const labelId = id + key;
    return <div className="vx-history-option">
      <span className="vx-history-option-label" id={labelId}>{icon}{label}</span>
      <Select value={filters[key]} onValueChange={value => change({ ...filters, [key]: value })}>
        <SelectTrigger className="vx-history-option-trigger" aria-labelledby={labelId}>
          <SelectValue>{filters[key]}</SelectValue>
        </SelectTrigger>
        <SelectContent portalContainer={dialog} className="vx-history-option-menu" theme={theme} align="end" collisionPadding={12}
          onEscapeKeyDown={event => event.stopPropagation()}>
          {options[key].map((value, index) => {
            const description = key === "events" ? eventDescriptions[value as HistoryFilters["events"]] : undefined;
            const optionId = labelId + "-" + index;
            return <SelectItem key={value} value={value} textValue={value} aria-labelledby={optionId}
              aria-describedby={description ? optionId + "-description" : undefined}>
              <span id={optionId}>{value}</span>
              {description && <small id={optionId + "-description"} className="vx-history-choice-description">{description}</small>}
            </SelectItem>;
          })}
        </SelectContent>
      </Select>
    </div>;
  }

  return <>
    <button ref={trigger} type="button" className="vx-history-filter-button" aria-haspopup="dialog" aria-expanded={open}
      onClick={() => setOpen(true)}><ListFilter size={16} />Filters</button>
    {open && <dialog ref={setDialog} className="vx-history-dialog" aria-labelledby={id + "-title"}
      onCancel={event => { event.preventDefault(); setOpen(false); }}
      onKeyDown={event => { if (event.key === "Escape" && !event.defaultPrevented) setOpen(false); }}
      onClick={event => {
        if (event.target !== dialog || !dialog) return;
        const r = dialog.getBoundingClientRect();
        if (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom) setOpen(false);
      }}>
      <header><h2 id={id + "-title"}>Conversation filters</h2>
        <button type="button" aria-label="Close dialog" onClick={() => setOpen(false)}><X size={16} /></button>
      </header>
      <div className="vx-history-filter-body">
        {row("messages", "Messages", <Icon name="message" />)}
        {row("logs", "Logs", <Icon name="log" />)}
        {row("events", "Events", <Icon name="event" />)}
        {row("tools", "Tools", <Wrench aria-hidden="true" />)}
        {row("guardrails", "Guardrails", <ShieldCheck aria-hidden="true" />)}
        <footer className="vx-history-filter-footer">
          <button type="button" className="vx-history-reset-defaults" aria-disabled={atDefaults}
            onClick={atDefaults ? undefined : () => change(defaults)}>
            <RotateCcw aria-hidden="true" size={14} />Reset to defaults
          </button>
        </footer>
      </div>
    </dialog>}
  </>;
}
