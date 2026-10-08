import { useState } from "react";
import { Plus, Trash2 } from "lucide-react";
import { Button } from "../components/ui/button";
import { ChoiceField, NumberField, TextField } from "./editor-fields";
import type { JsonObject, JsonValue, SourceIssue } from "./types";

type Common = { label: string; path: string[]; disabled?: boolean; issues?: SourceIssue[] };
type ValueProps = Common & { value: JsonValue; onChange: (value: JsonValue) => void };
const kinds = ["String", "Number", "Boolean", "Null", "Object", "Array"];
function initialValue(kind: string): JsonValue {
  const values: Record<string, JsonValue> = { String: "", Number: 0, Boolean: false, Null: null, Object: {}, Array: [] };
  return values[kind] ?? null;
}
function valueKind(value: JsonValue): string {
  if (value === null) return "Null";
  if (Array.isArray(value)) return "Array";
  return typeof value === "object" ? "Object" : typeof value === "number" ? "Number" : typeof value === "boolean" ? "Boolean" : "String";
}

/** Typed JSON values shared by provider options and schema enumeration values. */
export function ValueFields({ value, onChange, ...props }: ValueProps) {
  return <div className="min-w-0 space-y-3">
    <ChoiceField {...props} label={`${props.label} type`} path={[...props.path, "$type"]} value={valueKind(value)} choices={kinds.map((kind) => ({ value: kind, label: kind }))} onChange={(kind) => onChange(initialValue(kind))} />
    {value === null ? <p className="text-xs text-muted-foreground" data-field-path={JSON.stringify(props.path)}>Null</p>
      : Array.isArray(value) ? <ArrayFields {...props} value={value} onChange={onChange} />
      : typeof value === "object" ? <ObjectFields {...props} value={value} onChange={(next) => onChange(next ?? {})} clearable={false} />
      : typeof value === "number" ? <NumberField {...props} value={value} onChange={(next) => onChange(next ?? 0)} />
      : typeof value === "boolean" ? <ChoiceField {...props} value={String(value)} choices={[{ value: "true", label: "True" }, { value: "false", label: "False" }]} onChange={(next) => onChange(next === "true")} />
      : <TextField {...props} value={value} onChange={onChange} />}
  </div>;
}

export function ArrayFields({ value, onChange, ...props }: Common & { value: JsonValue[]; onChange: (value: JsonValue[]) => void }) {
  return <div className="space-y-3">
    {value.map((item, index) => <div key={index} className="space-y-2 border-t pt-3">
      <div className="flex items-center justify-between gap-2"><span className="text-xs text-muted-foreground">Item {index + 1}</span><RemoveButton label={`${props.label} / ${index + 1}`} disabled={props.disabled} onClick={() => onChange(value.filter((_, position) => position !== index))} /></div>
      <ValueFields {...props} label={`${props.label} / ${index + 1}`} path={[...props.path, String(index)]} value={item} onChange={(next) => onChange(value.map((item, position) => position === index ? next : item))} />
    </div>)}
    <Button variant="outline" size="sm" disabled={props.disabled} onClick={() => onChange([...value, ""])} aria-label={`Add ${props.label} item`}><Plus />Add item</Button>
  </div>;
}

export function ObjectFields({ value, onChange, clearable = true, reservedKeys = [], ...props }: Common & { value?: JsonObject; onChange: (value: JsonObject | undefined) => void; clearable?: boolean; reservedKeys?: string[] }) {
  function add() {
    let index = 1;
    while (Object.hasOwn(value ?? {}, `option_${index}`) || reservedKeys.includes(`option_${index}`)) index++;
    onChange({ ...value, [`option_${index}`]: "" });
  }
  return <section aria-label={props.label} className="min-w-0 space-y-3">
    <div className="flex items-center justify-between gap-2"><h4 className="break-words text-sm font-medium">{props.label}</h4>
      {clearable && value !== undefined && <Button variant="ghost" size="sm" disabled={props.disabled} aria-label={`Clear ${props.label}`} onClick={() => onChange(undefined)}>Clear</Button>}
    </div>
    {Object.entries(value ?? {}).map(([key, item]) => <div key={key} className="space-y-3 border-t pt-3">
      <div className="flex items-end gap-2"><div className="min-w-0 flex-1"><ObjectKey {...props} name={key} names={[...Object.keys(value ?? {}), ...reservedKeys]} onRename={(next) => onChange(Object.fromEntries(Object.entries(value ?? {}).map(([name, item]) => [name === key ? next : name, item])))} /></div>
        <RemoveButton label={`${props.label} / ${key}`} disabled={props.disabled} onClick={() => { const next = { ...value }; delete next[key]; onChange(next); }} />
      </div>
      <ValueFields {...props} label={`${props.label} / ${key}`} path={[...props.path, key]} value={item} onChange={(next) => onChange({ ...value, [key]: next })} />
    </div>)}
    <Button variant="outline" size="sm" disabled={props.disabled} onClick={add} aria-label={`Add ${props.label} field`}><Plus />Add field</Button>
  </section>;
}

function ObjectKey({ name, names, onRename, ...props }: Common & { name: string; names: string[]; onRename: (next: string) => void }) {
  const [draft, setDraft] = useState(name);
  const [error, setError] = useState("");
  function commit() {
    if (draft !== name && names.includes(draft)) { setError("That field already exists."); return; }
    setError(""); if (draft !== name) onRename(draft);
  }
  return <div onBlur={commit} onKeyDown={(event) => { if (event.key === "Enter") { event.preventDefault(); commit(); } }}>
    <TextField {...props} label={`${props.label} / ${name} key`} path={[...props.path, name, "$key"]} value={draft} onChange={setDraft} />
    {error && <p role="alert" className="mt-1 text-xs text-destructive">{error}</p>}
  </div>;
}
function RemoveButton({ label, disabled, onClick }: { label: string; disabled?: boolean; onClick: () => void }) {
  return <Button variant="ghost" size="icon" disabled={disabled} aria-label={`Remove ${label}`} onClick={onClick}><Trash2 /></Button>;
}
