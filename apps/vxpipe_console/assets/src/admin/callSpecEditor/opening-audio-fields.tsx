import { Label } from "../components/ui/label";
import { Switch } from "../components/ui/switch";
import type { ModelCatalog } from "../modelCatalog";
import { CapabilityFields } from "./capability-fields";
import { ChoiceField, TextField } from "./editor-fields";
import { editSource } from "./editSource";
import type { InspectorProps } from "./inspectorTypes";
import type { OpeningAudio } from "./types";

const emptySpeech = () => ({ type: "text" as const, text: "", text_to_speech: { provider: "", model: "" } });
export function OpeningAudioFields({ document, onChange, issues, catalog, credentialNames }: InspectorProps & { catalog: ModelCatalog; credentialNames: Record<string, string[]> }) {
  const audio = document.source.opening_audio;
  function change(value: OpeningAudio | undefined) {
    onChange(editSource(document, (source) => { if (value === undefined) delete source.opening_audio; else source.opening_audio = value; }));
  }
  return <section className="space-y-4 rounded-md border border-border/70 bg-muted/30 p-3" aria-label="Opening audio">
    <Label className="text-sm font-medium"><Switch checked={Boolean(audio)} disabled={document.readOnly} aria-label="Opening audio" onCheckedChange={(enabled) => change(enabled ? emptySpeech() : undefined)} />Opening audio</Label>
    <p className="text-xs text-muted-foreground">Play an announcement before the conversation begins.</p>
    {audio && <div className="space-y-4 border-t border-border/70 pt-3">
      <ChoiceField label="Opening audio type" path={["opening_audio", "type"]} issues={issues} disabled={document.readOnly} value={audio.type}
        choices={[{ value: "text", label: "Spoken text" }, { value: "file_url", label: "Audio file URL" }]}
        onChange={(type) => change(type === "text" ? emptySpeech() : { type: "file_url", url: "" })} />
      {audio.type === "text" ? <>
        <TextField multiline label="Opening message" path={["opening_audio", "text"]} issues={issues} disabled={document.readOnly} value={audio.text} onChange={(text) => change({ ...audio, text })} />
        <p className="text-xs text-muted-foreground">Choose the voice for this announcement. Opening audio uses its own text-to-speech selection.</p>
        <CapabilityFields kind="text_to_speech" path={["opening_audio", "text_to_speech"]} value={audio.text_to_speech.provider ? audio.text_to_speech : undefined} catalog={catalog} credentialNames={credentialNames} disabled={document.readOnly} issues={issues} defaultLabel="Choose a provider"
          onChange={(selection) => change({ ...audio, text_to_speech: selection ?? { provider: "", model: "" } })} />
      </> : <TextField label="Audio file URL" path={["opening_audio", "url"]} issues={issues} disabled={document.readOnly} value={audio.url} hint="Use an HTTP or HTTPS URL." onChange={(url) => change({ ...audio, url })} />}
    </div>}
  </section>;
}
