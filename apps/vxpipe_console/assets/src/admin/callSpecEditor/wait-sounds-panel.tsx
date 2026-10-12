import { useId, useState } from "react";
import { Pencil } from "lucide-react";
import phoneRing from "../../../../../vxpipe_call_engine/priv/audio/wait_sounds/phone-ring.wav";
import cafeBossa from "../../../../../vxpipe_call_engine/priv/audio/wait_sounds/cafe-bossa.wav";
import { Button } from "../components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "../components/ui/select";
import { setWaitSounds } from "./edits";
import { useIssueField } from "./issue-context";
import { validateSource } from "./validation";
import { useWaitSoundPreview } from "./wait-sound-preview";
import { WaitSoundPreviewButton } from "./wait-sound-preview-button";
import { WaitSoundUrlDialog } from "./wait-sound-url-dialog";
import type { InspectorProps } from "./inspectorTypes";
import type { SourceIssue, WaitSoundSlot } from "./types";

const slots: [WaitSoundSlot, string][] = [["call_setup", "Call setup"], ["transfer_to_agent", "Transfer to agent"], ["transfer_to_human", "Transfer to human"], ["transfer_joining", "Transfer joining"]];
// Vite supplies an absolute asset path; esbuild supplies a path beside admin.js.
const builtIn = { ring: new URL(phoneRing, import.meta.url).href, bossa: new URL(cafeBossa, import.meta.url).href };

export function WaitSoundsPanel({ document, onChange, issues }: InspectorProps) {
  const [editing, setEditing] = useState<WaitSoundSlot | null>(null);
  const preview = useWaitSoundPreview();
  function change(slot: WaitSoundSlot, value: string | null | undefined) {
    preview.stop();
    const sounds = document.source.wait_sounds === null ? Object.fromEntries(slots.map(([key]) => [key, null])) : { ...document.source.wait_sounds };
    if (value === undefined) delete sounds[slot]; else sounds[slot] = value;
    onChange(setWaitSounds(document, Object.keys(sounds).length ? sounds : undefined));
  }
  return <div className="space-y-3">
    <p className="text-xs text-muted-foreground">Choose what callers hear while the call or a transfer is being prepared.</p>
    {slots.map(([slot, label]) => <WaitSoundRow key={slot} slot={slot} label={label}
      value={document.source.wait_sounds === null ? null : document.source.wait_sounds?.[slot]}
      readOnly={document.readOnly} issues={issues} preview={preview} onChange={(value) => change(slot, value)}
      onEdit={() => { preview.stop(); setEditing(slot); }} />)}
    {editing && <WaitSoundUrlDialog label={slots.find(([slot]) => slot === editing)![1]} initial={document.source.wait_sounds?.[editing] ?? ""}
      validate={(url) => validateSource({ ...document.source, wait_sounds: { [editing]: url } }).find((issue) => issue.path[0] === "wait_sounds")?.reason}
      onCancel={() => setEditing(null)} onSave={(url) => { change(editing, url); setEditing(null); }} />}
  </div>;
}

function WaitSoundRow({ slot, label, value, readOnly, issues, preview, onChange, onEdit }: {
  slot: WaitSoundSlot; label: string; value: string | null | undefined; readOnly?: boolean; issues?: SourceIssue[];
  preview: ReturnType<typeof useWaitSoundPreview>; onChange: (value: null | undefined) => void; onEdit: () => void;
}) {
  const id = useId();
  const { ref, errors } = useIssueField(["wait_sounds", slot], issues);
  const ring = slot === "call_setup" || slot === "transfer_to_human";
  const mode = value === undefined ? "default" : value === null ? "silence" : "url";
  const active = preview.active === slot;
  const error = preview.error?.id === slot ? preview.error.message : undefined;
  return <div ref={ref} tabIndex={-1} data-field-path={JSON.stringify(["wait_sounds", slot])} className="grid grid-cols-[8.5rem_minmax(0,1fr)_2.25rem] items-center gap-x-2 gap-y-1 outline-none focus-visible:ring-2 focus-visible:ring-ring">
    <label htmlFor={id} className="text-sm font-medium leading-snug">{label}</label>
    <div className="flex min-w-0 items-center rounded-md border border-input bg-input/30" title={typeof value === "string" ? value : undefined}>
      <Select value={mode} disabled={readOnly} onValueChange={(mode) => mode === "url" ? onEdit() : onChange(mode === "silence" ? null : undefined)}>
        <SelectTrigger id={id} aria-invalid={errors.length > 0} aria-describedby={errors.length || error ? `${id}-error` : undefined} className="min-w-0 flex-1 border-0 bg-transparent px-2 text-sm shadow-none dark:bg-transparent"><SelectValue /></SelectTrigger>
        <SelectContent>
          <SelectItem value="default">{ring ? "Phone ring" : "Cafe bossa"}</SelectItem>
          <SelectItem value="silence">Silence</SelectItem>
          <SelectItem value="url">Audio URL</SelectItem>
        </SelectContent>
      </Select>
      {typeof value === "string" && <Button type="button" variant="ghost" size="icon-sm" disabled={readOnly} aria-label={`Edit ${label} audio URL`} title="Edit audio URL" onClick={onEdit}><Pencil className="size-3.5" /></Button>}
    </div>
    <WaitSoundPreviewButton label={label} silent={value === null} disabled={value === null || value === ""} active={active} preview={preview}
      onClick={() => preview.toggle(slot, value ?? (ring ? builtIn.ring : builtIn.bossa))} />
    {(errors.length > 0 || error) && <div id={`${id}-error`} className="col-span-3 text-xs text-destructive" role="alert">{errors.map((issue, index) => <p key={index}>{issue.reason}</p>)}{error && <p>{error}</p>}</div>}
  </div>;
}
