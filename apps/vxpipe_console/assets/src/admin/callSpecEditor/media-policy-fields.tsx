import { ChoiceField } from "./editor-fields";
import { setMediaPolicy } from "./edits";
import type { InspectorProps } from "./inspectorTypes";
import type { MediaPolicy } from "./types";

export function MediaPolicyFields({ document, onChange, issues, participantKey }: InspectorProps & { participantKey: string | null }) {
  const policy = participantKey === null ? document.source.media_policy : document.source.participants[participantKey]?.while_present;
  const path = participantKey === null ? ["media_policy"] : ["participants", participantKey, "while_present"];
  function change(edit: (next: MediaPolicy) => void) {
    const next = structuredClone(policy ?? {}); edit(next);
    onChange(setMediaPolicy(document, participantKey, Object.keys(next).length ? next : undefined));
  }
  if (participantKey !== null) {
    const value = policy?.record_audio === false ? "deny" : "";
    return <fieldset disabled={document.readOnly} className="space-y-5">
      <p className="text-xs text-muted-foreground">These overrides apply while this participant is present. Inherit keeps the call-wide policy. Don&apos;t record silences all tracks while this participant is present.</p>
      <ChoiceField label="Record audio" path={[...path, "record_audio"]} issues={issues} disabled={document.readOnly}
        layout="responsive-inline" labelClassName="sm:w-36"
        value={value} choices={[{ value: "", label: "Inherit" }, { value: "deny", label: "Don't record" }]}
        onChange={(next) => change((draft) => { if (!next) delete draft.record_audio; else draft.record_audio = false; })} />
      <SaveTranscriptsField policy={policy} path={path} issues={issues} disabled={document.readOnly} inheritance={[{ value: "", label: "Inherit" }]} onSave={(save) => change((draft) => { if (save === undefined) delete draft.save_transcripts; else draft.save_transcripts = save; })} />
    </fieldset>;
  }
  const recordValue = policy?.record_audio === true ? "on" : "off";
  return <fieldset disabled={document.readOnly} className="space-y-5">
    <p className="text-xs text-muted-foreground">Recording is opt-in. Turn recording on to capture this call as a downloadable Matroska file with one track per participant connection plus a room track. Off is the default and records nothing. Reconnected connections get suffixed names such as caller-1.</p>
    <ChoiceField label="Record audio" path={[...path, "record_audio"]} issues={issues} disabled={document.readOnly}
      layout="responsive-inline" labelClassName="sm:w-36"
      value={recordValue} choices={[{ value: "on", label: "On" }, { value: "off", label: "Off" }]}
      onChange={(next) => change((draft) => { if (next === "on") draft.record_audio = true; else delete draft.record_audio; })} />
    <SaveTranscriptsField policy={policy} path={path} issues={issues} disabled={document.readOnly} onSave={(save) => change((draft) => { if (save === undefined) delete draft.save_transcripts; else draft.save_transcripts = save; })} />
  </fieldset>;
}

function SaveTranscriptsField({ policy, path, issues, disabled, onSave, inheritance = [] }: {
  policy: MediaPolicy | undefined;
  path: string[];
  issues: InspectorProps["issues"];
  disabled?: boolean;
  onSave: (save: boolean | undefined) => void;
  inheritance?: { value: string; label: string }[];
}) {
  const value = policy?.save_transcripts === undefined
    ? (inheritance.length > 0 ? "" : "allow")
    : policy.save_transcripts ? "allow" : "deny";
  return <ChoiceField label="Save transcripts" path={[...path, "save_transcripts"]} issues={issues} disabled={disabled}
    layout="responsive-inline" labelClassName="sm:w-36"
    value={value}
    choices={[...inheritance, { value: "allow", label: "Allow" }, { value: "deny", label: "Deny" }]}
    onChange={(next) => { if (!next) onSave(undefined); else onSave(next === "allow"); }} />;
}
