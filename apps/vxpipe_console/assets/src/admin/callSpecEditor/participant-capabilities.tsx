import { catalogCapabilities, type CatalogCapability, type ModelCatalog } from "../modelCatalog";
import { CapabilityFields } from "./capability-fields";
import { participant, setCapability } from "./edits";
import type { InspectorProps } from "./inspectorTypes";

const labels: Record<CatalogCapability, string> = { speech_to_text: "Speech to text", output_speech_to_text: "Output speech to text", text_to_speech: "Text to speech", speech_to_speech: "Speech to speech", model_inference: "Language model" };
export function ParticipantCapabilities({ document, onChange, issues, participantKey, catalog, credentialNames }: InspectorProps & { participantKey: string; catalog: ModelCatalog; credentialNames: Record<string, string[]> }) {
  const target = participant(document.source, participantKey);
  return <div className="space-y-6">{catalogCapabilities.map((kind) => {
    const inherited = document.source.defaults?.capabilities?.[kind];
    const providers = catalog[kind] ?? {};
    const models = inherited && Object.hasOwn(providers, inherited.provider) ? providers[inherited.provider] : undefined;
    const voices = models?.find((model) => model.id === inherited?.model)?.voices;
    const voice = voices && inherited?.options?.[voices.parameter];
    const defaultDescription = inherited ? `${inherited.provider} · ${inherited.model}${typeof voice === "string" ? ` · ${voice}` : ""}` : undefined;
    return <section key={kind} aria-label={labels[kind]} className="space-y-3 border-t pt-4">
      <h3 className="text-sm font-semibold">{labels[kind]}</h3>
      <p className="wrap-anywhere text-xs text-muted-foreground">{target.capabilities?.[kind] ? "Participant override" : defaultDescription ? `Inherited: ${defaultDescription}` : "No call default configured"}</p>
      {target.capabilities?.[kind] && defaultDescription && <p className="wrap-anywhere text-xs text-muted-foreground">Call default: {defaultDescription}</p>}
      <CapabilityFields kind={kind} path={["participants", participantKey, "capabilities", kind]} value={target.capabilities?.[kind]} catalog={catalog} credentialNames={credentialNames} issues={issues} disabled={document.readOnly}
        onChange={(selection) => onChange(setCapability(document, participantKey, kind, selection))} />
    </section>;
  })}</div>;
}
