import { useId, useState } from "react";
import { X } from "lucide-react";
import { Button } from "../components/ui/button";
import { useIssueField } from "./issue-context";
import { enumValueKey, enumValueLabel, parseEnumValue } from "./variable-enum-values";
import type { JsonValue, SourceIssue, VariableType } from "./types";

export function VariableEnumInput({ label, path, value, type, disabled, issues, onChange }: {
  label: string; path: string[]; value: JsonValue[]; type?: VariableType; disabled?: boolean; issues?: SourceIssue[]; onChange: (values: JsonValue[]) => void;
}) {
  const id = useId();
  const { ref, errors } = useIssueField(path, issues);
  const [draft, setDraft] = useState("");
  const [error, setError] = useState<string>();
  function add() {
    try {
      const next = parseEnumValue(draft, type);
      if (value.some(item => enumValueKey(item) === enumValueKey(next))) throw new Error("That value is already listed.");
      onChange([...value, next]); setDraft(""); setError(undefined);
    } catch (failure) { setError(failure instanceof Error ? failure.message : "Enter a valid value."); }
  }
  return <div ref={ref} tabIndex={-1} data-field-path={JSON.stringify(path)} className="grid grid-cols-1 items-start gap-x-3 gap-y-2 outline-none sm:grid-cols-[6rem_minmax(0,1fr)]">
    <label htmlFor={id} className="text-sm font-medium sm:pt-2">Valid values</label>
    <div className="flex min-w-0 min-h-9 flex-wrap items-center gap-1 rounded-md border border-input bg-input/30 p-1.5 focus-within:border-ring">
      {value.map((item, index) => <span key={index} className="inline-flex max-w-full items-center gap-1 rounded bg-secondary pl-2 text-xs text-secondary-foreground">
        <span className="min-w-0 break-all py-1">{enumValueLabel(item)}</span>
        <Button type="button" variant="ghost" size="icon-xs" disabled={disabled} aria-label={`Remove valid value ${enumValueLabel(item)}`} onClick={() => onChange(value.filter((_, position) => position !== index))}><X className="size-3" /></Button>
      </span>)}
      <input id={id} aria-label={`${label} valid values`} aria-invalid={!!error || errors.length > 0} aria-describedby={error || errors.length || type !== "string" ? `${id}-help` : undefined} disabled={disabled} value={draft}
        placeholder="Type a value, press Enter" className="h-7 min-w-0 flex-[1_1_10rem] bg-transparent px-1 text-sm outline-none placeholder:text-muted-foreground disabled:opacity-50"
        onChange={(event) => { setDraft(event.target.value); setError(undefined); }}
        onKeyDown={(event) => { if (event.key === "Enter" && !event.nativeEvent.isComposing) { event.preventDefault(); add(); } }} />
    </div>
    {(error || errors.length > 0 || type !== "string") && <div id={`${id}-help`} className="text-xs sm:col-start-2">
      {error && <p role="alert" className="text-destructive">{error}</p>}
      {errors.map((issue, index) => <p key={index} className="text-destructive">{issue.reason}</p>)}
      {!error && type !== "string" && <p className="text-muted-foreground">{type === "boolean" ? "Enter true or false." : type === "object" || type === "array" || !type ? "Enter each value as JSON." : `Enter ${type} values.`}</p>}
    </div>}
  </div>;
}
