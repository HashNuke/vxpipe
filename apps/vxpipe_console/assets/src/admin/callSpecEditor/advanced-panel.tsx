import { ChoiceField, NumberField } from "./editor-fields";
import { editSource } from "./editSource";
import type { InspectorProps } from "./inspectorTypes";
import type { Visibility } from "./types";
const levels = [{ value: "hidden", label: "Hidden" }, { value: "metadata", label: "Metadata" }, { value: "full", label: "Full" }];
export function AdvancedPanel({ document, onChange, issues }: InspectorProps) {
  const { source, readOnly } = document;
  return <fieldset disabled={readOnly} className="space-y-5">
    <p className="text-xs text-muted-foreground">Schema {source.schema_version}</p>
    <ChoiceField label="Default tool visibility" path={["tool_visibility"]} issues={issues} disabled={readOnly} value={source.tool_visibility ?? ""} choices={[{ value: "", label: "Default (hidden)" }, ...levels]}
      onChange={(value) => onChange(editSource(document, (next) => { if (!value) delete next.tool_visibility; else next.tool_visibility = value as Visibility; }))} />
    {Object.entries(source.participants).filter(([, participant]) => participant.type === "agent").map(([key, participant]) => {
      if (participant.type !== "agent") return null;
      const overrides = source.tool_visibility_overrides;
      const ownOverrides = overrides && Object.hasOwn(overrides, key) ? overrides[key] : undefined;
      const tools = [...new Set([...Object.keys(participant.tools ?? {}), ...(participant.transfers?.length ? ["transfer"] : []), ...Object.keys(ownOverrides ?? {})])];
      return tools.length > 0 && <section key={key} className="space-y-3 border-t pt-4"><h3 className="text-sm font-semibold">{key} tools</h3>{tools.map((tool) => <ChoiceField key={tool} label={`${key} / ${tool} visibility`} path={["tool_visibility_overrides", key, tool]} issues={issues} disabled={readOnly}
        value={ownOverrides && Object.hasOwn(ownOverrides, tool) ? ownOverrides[tool]! : ""} choices={[{ value: "", label: "Inherit default" }, ...levels]} onChange={(value) => onChange(editSource(document, (next) => {
          const overrides = next.tool_visibility_overrides ?? {};
          const byTool = { ...(Object.hasOwn(overrides, key) ? overrides[key] : {}) };
          if (!value) delete byTool[tool];
          next.tool_visibility_overrides = { ...overrides, [key]: value ? { ...byTool, [tool]: value as Visibility } : byTool };
        }))} />)}</section>;
    })}
    <NumberField label="Maximum call duration (ms)" path={["limits", "max_duration_ms"]} issues={issues} disabled={readOnly} hint="Leave blank to use the runtime default." value={source.limits?.max_duration_ms}
      onChange={(value) => onChange(editSource(document, (next) => { next.limits ??= {}; if (value === undefined) delete next.limits.max_duration_ms; else next.limits.max_duration_ms = value; }))} />
    <NumberField label="Transfer attempt timeout (ms)" path={["transfer_policy", "attempt_timeout_ms"]} issues={issues} disabled={readOnly} hint="1,000–120,000 ms. Leave blank to use the runtime default." value={source.transfer_policy?.attempt_timeout_ms}
      onChange={(value) => onChange(editSource(document, (next) => { next.transfer_policy ??= {}; if (value === undefined) delete next.transfer_policy.attempt_timeout_ms; else next.transfer_policy.attempt_timeout_ms = value; }))} />
  </fieldset>;
}
