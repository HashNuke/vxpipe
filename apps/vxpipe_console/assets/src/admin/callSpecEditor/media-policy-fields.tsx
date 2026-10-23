import { ChoiceField } from "./editor-fields";
import { setMediaPolicy } from "./edits";
import type { InspectorProps } from "./inspectorTypes";
import type { MediaPolicy } from "./types";

export function MediaPolicyFields({ document, onChange, issues, participantKey }: InspectorProps & { participantKey: string | null }) {
  const policy = participantKey === null ? document.source.media_policy : document.source.participants[participantKey]?.while_present;
  const path = participantKey === null ? ["media_policy"] : ["participants", participantKey, "while_present"];
  const inheritance = participantKey === null ? [] : [{ value: "", label: "Inherit" }];
  function change(edit: (next: MediaPolicy) => void) {
    const next = structuredClone(policy ?? {}); edit(next);
    onChange(setMediaPolicy(document, participantKey, Object.keys(next).length ? next : undefined));
  }
  return <fieldset disabled={document.readOnly} className="space-y-5">
    <p className="text-xs text-muted-foreground">{participantKey === null ? "Set recording and transcript storage permissions for this call." : "These overrides apply while this participant is present. Inherit keeps the call-wide policy."}</p>
    {(["record_audio", "save_transcripts"] as const).map((key) => <ChoiceField key={key} label={key === "record_audio" ? "Record audio" : "Save transcripts"} path={[...path, key]} issues={issues} disabled={document.readOnly}
      layout="responsive-inline" labelClassName="sm:w-36"
      value={policy?.[key] === undefined ? participantKey === null ? "allow" : "" : policy[key] ? "allow" : "deny"} choices={[...inheritance, { value: "allow", label: "Allow" }, { value: "deny", label: "Deny" }]}
      onChange={(value) => change((next) => { if (!value) delete next[key]; else next[key] = value === "allow"; })} />)}
  </fieldset>;
}
