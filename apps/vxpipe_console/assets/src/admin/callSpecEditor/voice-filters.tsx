import { useId } from "react";
import { Input } from "../components/ui/input";
import { Label } from "../components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../components/ui/select";
import type { VoiceFilter, VoiceFilters } from "../voiceCatalog";
import { VoiceFilterSelect } from "./voice-filter-select";

export function VoiceFilterControl({ filter, value, onChange }: { filter: VoiceFilter; value: VoiceFilters[string] | undefined; onChange: (value: VoiceFilters[string] | undefined) => void }) {
  const id = useId();
  if (filter.type === "select" || filter.type === "multi_select") return <div className="min-w-0 space-y-1.5">
    <Label htmlFor={id} className="text-xs text-muted-foreground">{filter.label}</Label>
    <VoiceFilterSelect id={id} label={filter.label} options={filter.options} multiple={filter.type === "multi_select"}
      value={typeof value === "string" || Array.isArray(value) ? value : undefined} onChange={onChange} />
  </div>;
  const options = [{ value: "true", label: "Yes" }, { value: "false", label: "No" }];
  return <div className="min-w-0 space-y-1.5"><Label htmlFor={id} className="text-xs text-muted-foreground">{filter.label}</Label>
    {filter.type === "boolean" ? <Select value={value === undefined ? "\u0001all" : String(value)} onValueChange={next => onChange(next === "\u0001all" ? undefined : next === "true")}>
      <SelectTrigger id={id} size="sm" className="w-full text-xs"><SelectValue /></SelectTrigger>
      <SelectContent><SelectItem className="text-xs" value={"\u0001all"}>Any</SelectItem>{options.map(option => <SelectItem className="text-xs" key={option.value} value={option.value}>{option.label}</SelectItem>)}</SelectContent>
    </Select> : <Input id={id} className="h-8 text-xs md:text-xs" type={filter.type === "number" ? "number" : "text"} value={value === undefined ? "" : String(value)}
      placeholder={filter.type === "text" ? filter.placeholder : undefined} min={filter.type === "number" ? filter.min : undefined} max={filter.type === "number" ? filter.max : undefined}
      onChange={event => onChange(event.target.value === "" ? undefined : filter.type === "number" ? Number(event.target.value) : event.target.value)} />}
  </div>;
}
