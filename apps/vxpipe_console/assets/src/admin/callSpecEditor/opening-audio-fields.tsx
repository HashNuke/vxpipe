import { Label } from "../components/ui/label";
import { Switch } from "../components/ui/switch";
import { ChoiceField, TextField } from "./editor-fields";
import { editSource } from "./editSource";
import type { InspectorProps } from "./inspectorTypes";
import type { OpeningAudio } from "./types";

export function OpeningAudioFields({ document, onChange, issues, onOpenModels }: InspectorProps & { onOpenModels: () => void }) {
  const { source, readOnly } = document;
  const audio = source.opening_audio;
  const current = source.schema_version === "20261128.01" || source.schema_version === "20261125.01";
  const defaults = source.defaults?.capabilities;
  const speechToSpeech = Boolean(defaults?.speech_to_speech);
  const spokenAvailable = !speechToSpeech && Boolean(defaults?.text_to_speech);
  const conflict = current && !spokenAvailable && audio?.type === "text";
  function change(value?: OpeningAudio) {
    onChange(editSource(document, (next) => { if (value === undefined) delete next.opening_audio; else next.opening_audio = value; }));
  }
  return <section className="space-y-4 rounded-md border border-border/70 bg-muted/30 p-3" aria-label="Opening audio">
    <Label className="text-sm font-medium"><Switch checked={Boolean(audio)} disabled={readOnly} aria-label="Opening audio" onCheckedChange={(enabled) => change(enabled ? (spokenAvailable ? { type: "text", text: "" } : { type: "file_url", url: "" }) : undefined)} />Opening audio</Label>
    <p className="text-xs text-muted-foreground">Play an announcement before the conversation begins.</p>
    {audio && <div className="space-y-4 border-t border-border/70 pt-3">
      <ChoiceField label="Opening audio type" path={["opening_audio", "type"]} issues={issues} disabled={readOnly} value={audio.type}
        choices={[{ value: "none", label: "None" }, { value: "text", label: "Spoken text", disabled: current && !spokenAvailable }, { value: "file_url", label: "Audio file URL" }]}
        onChange={(type) => change(type === "none" ? undefined : type === "text" ? { type: "text", text: "" } : { type: "file_url", url: "" })} />
      {current && !spokenAvailable && <p className="text-xs text-muted-foreground">
        {conflict ? "Your spoken opening can’t play with the current model. Choose Audio file URL or None, or select a text-to-speech model before publishing."
          : speechToSpeech ? "Spoken text requires a text-to-speech model. This call uses speech-to-speech."
          : "To use spoken text, select a default text-to-speech model."}{" "}
        <button type="button" className="underline underline-offset-2" onClick={onOpenModels}>Call settings → Models</button>
      </p>}
      {audio.type === "text" ? <>
        <TextField multiline label="Opening message" path={["opening_audio", "text"]} issues={issues} disabled={readOnly} value={audio.text} onChange={(text) => change({ ...audio, text })} />
        {!current && audio.text_to_speech && <p className="text-xs text-muted-foreground">Saved opening voice: {audio.text_to_speech.provider} / {audio.text_to_speech.model}</p>}
      </> : <TextField label="Audio file URL" path={["opening_audio", "url"]} issues={issues} disabled={readOnly} value={audio.url} hint="Use an HTTPS URL." onChange={(url) => change({ ...audio, url })} />}
    </div>}
  </section>;
}
