import { ChoiceField, TextField } from "./editor-fields";
import { setWaitSounds } from "./edits";
import type { InspectorProps } from "./inspectorTypes";
import type { WaitSoundSlot } from "./types";
const slots: [WaitSoundSlot, string][] = [["call_setup", "Call setup"], ["transfer_to_agent", "Transfer to agent"], ["transfer_to_human", "Transfer to human"], ["transfer_joining", "Transfer joining"]];
export function WaitSoundsPanel({ document, onChange, issues }: InspectorProps) {
  function change(slot: WaitSoundSlot, value: string | null | undefined) {
    const sounds = document.source.wait_sounds === null ? Object.fromEntries(slots.map(([key]) => [key, null])) : { ...document.source.wait_sounds };
    if (value === undefined) delete sounds[slot]; else sounds[slot] = value;
    onChange(setWaitSounds(document, Object.keys(sounds).length ? sounds : undefined));
  }
  return <fieldset disabled={document.readOnly} className="space-y-5">
    <p className="text-xs text-muted-foreground">Choose what callers hear while the call or a transfer is being prepared.</p>
    {slots.map(([slot, label]) => {
      const value = document.source.wait_sounds === null ? null : document.source.wait_sounds?.[slot];
      return <div key={slot} className="space-y-3 rounded-md border p-3">
        <ChoiceField label={label} path={typeof value === "string" ? ["wait_sounds", slot, "mode"] : ["wait_sounds", slot]} issues={issues} disabled={document.readOnly} value={value === undefined ? "default" : value === null ? "silence" : "url"}
          choices={[{ value: "default", label: "Built-in default" }, { value: "silence", label: "Silence" }, { value: "url", label: "Audio URL" }]}
          onChange={(mode) => change(slot, mode === "default" ? undefined : mode === "silence" ? null : typeof value === "string" ? value : "")} />
        {typeof value === "string" && <TextField label={`${label} URL`} path={["wait_sounds", slot]} issues={issues} disabled={document.readOnly} value={value} onChange={(url) => change(slot, url)} hint="An HTTP(S) audio-file URL." />}
      </div>;
    })}
  </fieldset>;
}
