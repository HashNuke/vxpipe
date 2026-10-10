import type { CatalogCapability, ModelCatalog } from "../modelCatalog";
import { CapabilityFields } from "./capability-fields";
import { setCapability } from "./edits";
import type { InspectorProps } from "./inspectorTypes";

type DefaultModelKind = Exclude<CatalogCapability, "output_speech_to_text">;
type DefaultsPanelProps = InspectorProps & { catalog: ModelCatalog };

const labels: Record<DefaultModelKind, string> = {
  speech_to_text: "Speech to text",
  text_to_speech: "Text to speech",
  speech_to_speech: "Speech to speech",
  model_inference: "Language model",
};
export function DefaultsPanel(props: DefaultsPanelProps) {
  return <div className="space-y-6">
    <p className="text-xs text-muted-foreground">Participants inherit these models unless they choose their own provider and model.</p>
    <section aria-label="AI agents" className="space-y-6 rounded-md border p-4">
      <h3 className="text-base font-semibold">AI agents</h3>
      <fieldset className="min-w-0">
        <legend className="mb-4 text-sm font-semibold">LLM + Text-to-Speech</legend>
        <div className="space-y-6">
          <DefaultCapability {...props} kind="model_inference" />
          <DefaultCapability {...props} kind="text_to_speech" />
        </div>
      </fieldset>
      <fieldset className="min-w-0">
        <legend className="mb-4 text-sm font-semibold">Speech-to-Speech</legend>
        <DefaultCapability {...props} kind="speech_to_speech" showHeading={false} />
      </fieldset>
    </section>
    <section aria-label="Human participants" className="space-y-6 rounded-md border p-4">
      <div className="space-y-1">
        <h3 className="text-base font-semibold">Human participants</h3>
        <p className="text-xs text-muted-foreground">Transcribes speech from callers and other human participants.</p>
      </div>
      <DefaultCapability {...props} kind="speech_to_text" />
    </section>
  </div>;
}

function DefaultCapability({ document, onChange, issues, catalog, kind, showHeading = true }: DefaultsPanelProps & { kind: DefaultModelKind; showHeading?: boolean }) {
  return <section aria-label={labels[kind]} className="space-y-3">
    {showHeading && <h4 className="text-sm font-medium">{labels[kind]}</h4>}
    <CapabilityFields kind={kind} path={["defaults", "capabilities", kind]} value={document.source.defaults?.capabilities?.[kind]}
      onChange={(selection) => onChange(setCapability(document, null, kind, selection))} catalog={catalog}
      issues={issues} disabled={document.readOnly} defaultLabel="Not configured" />
  </section>;
}
