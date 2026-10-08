import { catalogCapabilities, type CatalogCapability, type ModelCatalog } from "../modelCatalog";
import { CapabilityFields } from "./capability-fields";
import { setCapability } from "./edits";
import type { InspectorProps } from "./inspectorTypes";

const labels: Record<CatalogCapability, string> = {
  speech_to_text: "Speech to text",
  output_speech_to_text: "Output speech to text",
  text_to_speech: "Text to speech",
  speech_to_speech: "Speech to speech",
  model_inference: "Language model",
};
export function DefaultsPanel({ document, onChange, issues, catalog, credentialNames }: InspectorProps & { catalog: ModelCatalog; credentialNames: Record<string, string[]> }) {
  return <div className="space-y-6">
    <p className="text-xs text-muted-foreground">Participants inherit these capabilities unless they choose their own provider and model.</p>
    {catalogCapabilities.map((kind) => <section key={kind} aria-label={labels[kind]} className="space-y-3 border-t pt-4">
      <h3 className="text-sm font-semibold">{labels[kind]}</h3>
      <CapabilityFields kind={kind} path={["defaults", "capabilities", kind]} value={document.source.defaults?.capabilities?.[kind]}
        onChange={(selection) => onChange(setCapability(document, null, kind, selection))} catalog={catalog} credentialNames={credentialNames}
        issues={issues} disabled={document.readOnly} defaultLabel="Not configured" />
    </section>)}
  </div>;
}
