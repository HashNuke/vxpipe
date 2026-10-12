import { parseSourceNumber } from "./source-json";
import { useId, type ReactNode } from "react";
import { Input } from "../components/ui/input";
import { Textarea } from "../components/ui/textarea";
import { Label } from "../components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../components/ui/select";
import { useIssueField } from "./issue-context";
import type { SourceIssue } from "./types";

type FieldProps = { label: string; displayLabel?: string; labelClassName?: string; path: string[]; issues?: SourceIssue[]; hint?: string; disabled?: boolean; labelHidden?: boolean; layout?: "stacked" | "inline" | "responsive-inline" };
type ControlProps = { id: string; "aria-describedby"?: string; "aria-invalid"?: boolean; disabled?: boolean };
function Field({ label, displayLabel, path, issues = [], hint, disabled, labelHidden, labelClassName, layout = "stacked", children }: FieldProps & { children: (props: ControlProps) => ReactNode }) {
  const id = useId();
  const { ref, errors } = useIssueField(path, issues);
  return <div ref={ref} tabIndex={-1} className={`${layout === "responsive-inline" ? "grid grid-cols-1 items-center gap-x-3 gap-y-2 sm:grid-cols-[auto_minmax(0,1fr)]" : layout === "inline" ? "grid grid-cols-[auto_minmax(0,1fr)] items-center gap-x-3 gap-y-2" : "space-y-2"} outline-none focus-visible:ring-2 focus-visible:ring-ring`} data-field-path={JSON.stringify(path)}>
    <Label htmlFor={id} className={labelHidden ? "sr-only" : `wrap-anywhere leading-snug ${labelClassName ?? ""}`}>{displayLabel ? <><span aria-hidden="true">{displayLabel}</span><span className="sr-only">{label}</span></> : label}</Label>
    {children({ id, disabled, "aria-invalid": errors.length > 0, "aria-describedby": hint || errors.length ? `${id}-help` : undefined })}
    {(hint || errors.length > 0) && <div id={`${id}-help`} className={`${layout === "responsive-inline" ? "sm:col-span-2 " : layout === "inline" ? "col-span-2 " : ""}space-y-1 text-xs`}>
      {hint && <p className="text-muted-foreground">{hint}</p>}
      {errors.map((issue, index) => <p className="text-destructive" key={index}>{issue.reason}</p>)}
    </div>}
  </div>;
}
export function TextField({ value, onChange, multiline, rows, ...props }: FieldProps & { value: string; onChange: (value: string) => void; multiline?: boolean; rows?: number }) {
  return <Field {...props}>{(control) => multiline
    ? <Textarea {...control} rows={rows} value={value} onChange={(event) => onChange(event.target.value)} className={rows ? "field-sizing-fixed" : "min-h-28"} />
    : <Input {...control} value={value} onChange={(event) => onChange(event.target.value)} />}</Field>;
}
export function NumberField({ value, onChange, ...props }: FieldProps & { value?: number; onChange: (value: number | undefined) => void }) {
  return <Field {...props}>{(control) => <Input {...control} type="number" value={value ?? ""} onChange={(event) => onChange(event.target.value === "" ? undefined : Number(event.target.value))} />}</Field>;
}
/** Present seconds while keeping the call-spec contract in integer milliseconds. */
export function DurationField({ value, onChange, ...props }: FieldProps & { value?: number; onChange: (milliseconds: number | undefined) => void }) {
  return <Field {...props}>{(control) => <Input {...control} type="number" step="0.001" value={value === undefined ? "" : value / 1000} onChange={(event) => onChange(event.target.value === "" ? undefined : Math.round(Number(event.target.value) * 1000))} />}</Field>;
}
/** Unlike bounded timing controls, arbitrary source values must retain integer precision. */
export function SourceNumberField({ value, onChange, ...props }: FieldProps & { value?: number | bigint; onChange: (value: number | bigint | undefined) => void }) {
  return <Field {...props}>{(control) => <Input {...control} type="number" aria-valuetext={value === undefined ? undefined : String(value)} value={value === undefined ? "" : String(value)} onChange={(event) => onChange(event.target.value === "" ? undefined : parseSourceNumber(event.target.value))} />}</Field>;
}
export type Choice = { value: string; label: string; disabled?: boolean };
export function ChoiceField({ value, onChange, choices, ...props }: FieldProps & { value: string; onChange: (value: string) => void; choices: Choice[] }) {
  const unset = "\u0001unset";
  const options = choices.some((choice) => choice.value === value) ? choices : [...choices, { value, label: `${value} (saved)` }];
  return <Field {...props}>{(control) => <Select value={value || unset} onValueChange={(next) => onChange(next === unset ? "" : next)} disabled={props.disabled}>
    <SelectTrigger {...control} className="w-full min-w-0"><SelectValue /></SelectTrigger>
    <SelectContent>{options.map((choice) => <SelectItem key={choice.value} value={choice.value || unset} disabled={choice.disabled}>{choice.label}</SelectItem>)}</SelectContent>
  </Select>}</Field>;
}
