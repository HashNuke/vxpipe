import { ChoiceField, DurationField } from "./editor-fields";
import { editSource } from "./editSource";
import type { InspectorProps } from "./inspectorTypes";
import type { Visibility } from "./types";
const levels = [{ value: "hidden", label: "Hidden" }, { value: "metadata", label: "Metadata" }, { value: "full", label: "Full" }];
export function AdvancedPanel({ document, onChange, issues }: InspectorProps) {
  const { source, readOnly } = document;
  return <fieldset disabled={readOnly} className="space-y-5">
    <p className="text-xs text-muted-foreground">Schema {source.schema_version}</p>
    <ChoiceField layout="responsive-inline" labelClassName="sm:w-60" label="Default tool visibility" path={["tool_visibility"]} issues={issues} disabled={readOnly} value={source.tool_visibility ?? "hidden"} choices={levels}
      onChange={(value) => onChange(editSource(document, (next) => { if (value === "hidden") delete next.tool_visibility; else next.tool_visibility = value as Visibility; }))} />
    <DurationField layout="responsive-inline" labelClassName="sm:w-60" label="Max call duration (seconds)" path={["limits", "max_duration_ms"]} issues={issues} disabled={readOnly} hint="Leave blank to use the runtime default." value={source.limits?.max_duration_ms}
      onChange={(value) => onChange(editSource(document, (next) => { next.limits ??= {}; if (value === undefined) delete next.limits.max_duration_ms; else next.limits.max_duration_ms = value; }))} />
    <DurationField layout="responsive-inline" labelClassName="sm:w-60" label="Transfer attempt timeout (seconds)" path={["transfer_policy", "attempt_timeout_ms"]} issues={issues} disabled={readOnly} hint="1–120 seconds. Leave blank to use the runtime default." value={source.transfer_policy?.attempt_timeout_ms}
      onChange={(value) => onChange(editSource(document, (next) => { next.transfer_policy ??= {}; if (value === undefined) delete next.transfer_policy.attempt_timeout_ms; else next.transfer_policy.attempt_timeout_ms = value; }))} />
  </fieldset>;
}
