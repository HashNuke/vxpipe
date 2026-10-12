import type { CatalogCapability, ModelCatalog } from "../modelCatalog";
import { CapabilityFields } from "./capability-fields";
import { participant, setCapability } from "./edits";
import type { InspectorProps } from "./inspectorTypes";

const labels: Record<CatalogCapability, string> = { speech_to_text: "Speech to text", output_speech_to_text: "Output speech to text", text_to_speech: "Text to speech", speech_to_speech: "Speech to speech", model_inference: "Language model" };
export function ParticipantCapabilities({ document, onChange, issues, participantKey, catalog, kinds = ["speech_to_text"], required = false }: InspectorProps & { participantKey: string; catalog: ModelCatalog; kinds?: CatalogCapability[]; required?: boolean }) {
  const target = participant(document.source, participantKey);
  return <div className="space-y-6">{kinds.map((kind) => {
    const inherited = document.source.defaults?.capabilities?.[kind];
    return <section key={kind} aria-label={labels[kind]} className="space-y-3 border-t pt-4">
      <h3 className="text-sm font-semibold">{labels[kind]}</h3>
      <CapabilityFields kind={kind} path={["participants", participantKey, "capabilities", kind]} value={target.capabilities?.[kind] ?? inherited} catalog={catalog} issues={issues} disabled={document.readOnly}
        inherited={inherited} defaultLabel={required && !inherited ? "Choose provider" : "Not configured"} defaultDisabled={required && !inherited}
        onChange={(selection) => onChange(setCapability(document, participantKey, kind, selection))} />
    </section>;
  })}</div>;
}
