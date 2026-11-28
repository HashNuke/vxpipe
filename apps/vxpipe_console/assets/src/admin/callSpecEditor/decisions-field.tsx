import type { ModelCatalog } from "../modelCatalog";
import { CapabilityFields } from "./capability-fields";
import { ChoiceField } from "./editor-fields";
import { setCapability } from "./edits";
import type { InspectorProps } from "./inspectorTypes";

export function DecisionsCallField({ document, onChange, catalog, issues }: InspectorProps & { catalog: ModelCatalog }) {
  const value = document.source.defaults?.capabilities?.decisions;
  return <section aria-label="Decisions" className="space-y-3">
    <h4 className="text-sm font-medium">Decisions</h4>
    <CapabilityFields kind="decisions" path={["defaults", "capabilities", "decisions"]} value={value}
      onChange={(selection) => onChange(setCapability(document, null, "decisions", selection))} catalog={catalog}
      issues={issues} disabled={document.readOnly} defaultLabel="Choose provider" />
    <p className="text-xs text-muted-foreground">Used for guardrail checks across all AI agents in this call.</p>
  </section>;
}

export function DecisionsAgentField({ document, issues, participantKey }: InspectorProps & { participantKey: string }) {
  const effective = document.source.defaults?.capabilities?.decisions;
  return <ChoiceField label="Decisions" path={["participants", participantKey, "capabilities", "decisions"]}
    issues={issues} disabled value={effective?.model ?? ""}
    choices={effective ? [{ value: effective.model, label: `${effective.provider} · ${effective.model}` }] : [{ value: "", label: "Not configured", disabled: true }]}
    hint="Change the Decisions model in Call settings → Models."
    onChange={() => {}} />;
}
